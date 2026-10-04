import pychromecast
from pychromecast.config import APP_MEDIA_RECEIVER
from pychromecast.response_handler import WaitResponse
from pychromecast.controllers.multizone import MultizoneController
import pandas as pd
import time
import logging
from datetime import datetime, timedelta
import os
import random
import subprocess
import threading
from logging.handlers import RotatingFileHandler
from concurrent.futures import ThreadPoolExecutor, TimeoutError
from zeroconf import Zeroconf
from mutagen.easyid3 import EasyID3  # MP3 metadata
import configparser

# Connection-robustness notes:
#   - A single process-wide Zeroconf instance is kept open for the life of the
#     process. Closing it after connecting leaves the cast's socket worker with
#     a dead event loop, which turns every later disconnect into a tight
#     reconnect loop that floods the log.
#   - ZEROCONF_INTERFACE can bind mDNS to the LAN IP, keeping it off unusable
#     interfaces (e.g. VPN links that fail with OSError [Errno 126]).
#   - Discovery and connect are bounded by TIMEOUT/MAX_RETRIES; if the device
#     can't be reached the prayer is skipped, and playback is skipped when more
#     than MAX_LATE_SECONDS past the prayer time (no stale athan hours later).
#   - Waits re-check the wall clock in short chunks, and startup waits (bounded)
#     for NTP sync, so clock corrections and DST changes don't shift the athan.
#   - If another cast (e.g. a doorbell chime sent to a speaker group) interrupts
#     the athan, it waits for that cast to finish and resumes where it stopped.
#   - Repeated identical log lines are collapsed so a storm can't rotate real
#     history away.
# ================================
# Configuration File and Loading
# ================================
CONFIG_FILE = '/etc/athan-automation/config.ini'

def load_config():
    """
    Load configuration values from the ini file.
    Logs an error if the file is missing but continues with default values.
    """
    cp = configparser.ConfigParser()
    if not cp.read(CONFIG_FILE):
        logging.error(f"Configuration file not found: {CONFIG_FILE}. Using default values.")

    section = cp['DEFAULT']

    settings = {
        'FAJR_FOLDER': section.get('FAJR_FOLDER', '/var/www/html/athan/fajr'),
        'PRAYER_FOLDER': section.get('PRAYER_FOLDER', '/var/www/html/athan/prayer'),
        'IFTAR_FOLDER': section.get('IFTAR_FOLDER', '/var/www/html/athan/iftar'),
        'PRAYER_TIMES_FILE': os.path.expanduser(section.get('PRAYER_TIMES_FILE')),
        'LIGHTTPD_BASE_URL': section.get('LIGHTTPD_BASE_URL', "http://192.168.86.30/html/athan"),
        'ATHAN_ART_URL': section.get('ATHAN_ART_URL', "http://192.168.86.30/html/athan/Mohamed_Ali_Mosque.jpg"),
        'IFTAR_ART_URL': section.get('IFTAR_ART_URL', "http://192.168.86.30/html/athan/Iftar.jpg"),
        'ATHAN_DEVICE': section.get('ATHAN_DEVICE'),
        'IFTAR_DEVICE': section.get('IFTAR_DEVICE', 'All speakers'),
        'LOG_FILE': os.path.expanduser(section.get('LOG_FILE')),
        'ATHAN_VOLUME_LEVEL': section.getfloat('ATHAN_VOLUME_LEVEL', 0.3),
        'FAJR_VOLUME_LEVEL': section.getfloat('FAJR_VOLUME_LEVEL', 0.2),
        # LAN interface(s) Zeroconf/mDNS should bind to. Restricting to the
        # host's LAN IP keeps mDNS off unusable interfaces (e.g. a VPN link that
        # rejects sends with OSError [Errno 126]). Comma-separate for multiple;
        # leave blank to let Zeroconf use all interfaces.
        'ZEROCONF_INTERFACE': section.get('ZEROCONF_INTERFACE', ''),
        'MAX_RETRIES': section.getint('MAX_RETRIES', 3),      # discovery/connect attempts
        'TIMEOUT': section.getint('TIMEOUT', 30),             # seconds per connect attempt
        # If we only manage to connect this many seconds after the prayer time,
        # skip playback rather than playing a stale athan (e.g. Isha at Fajr).
        'MAX_LATE_SECONDS': section.getint('MAX_LATE_SECONDS', 600),
        # At startup, how long to wait for NTP sync before scheduling anyway.
        'CLOCK_SYNC_MAX_WAIT': section.getint('CLOCK_SYNC_MAX_WAIT', 300),
    }

    # Warn if the prayer times file is missing
    if not os.path.exists(settings['PRAYER_TIMES_FILE']):
        logging.warning(f"Prayer times file not found: {settings['PRAYER_TIMES_FILE']}.")

    last_mtime = os.stat(CONFIG_FILE).st_mtime if os.path.exists(CONFIG_FILE) else None
    return settings, last_mtime


current_config, last_mtime = load_config()

retry_delay = 5  # seconds between retries
SLEEP_CHUNK_SECONDS = 30  # max single sleep while waiting for a prayer

# ========================
# Logging Configuration
# ========================
max_log_size = 5 * 1024 * 1024  # 5 MB
backup_count = 10  # keep enough history to survive a burst of errors


class DuplicateRateLimitFilter(logging.Filter):
    """
    Collapse floods of identical log records (defense-in-depth against a storm).

    Within a rolling window at most ``max_per_window`` copies of a given
    (level, message) pass through; further duplicates are dropped and counted,
    then summarized on the next distinct record.
    """

    def __init__(self, max_per_window=5, window_seconds=10.0):
        super().__init__()
        self.max_per_window = max_per_window
        self.window_seconds = window_seconds
        self._key = None
        self._count = 0
        self._suppressed = 0
        self._window_start = 0.0

    def filter(self, record):
        now = time.monotonic()
        key = (record.levelno, record.getMessage())
        new_window = (key != self._key) or (now - self._window_start >= self.window_seconds)

        if new_window:
            if self._suppressed > 0:
                try:
                    record.msg = "%s  [previous identical message suppressed %d more times]" % (
                        record.getMessage(), self._suppressed)
                    record.args = ()
                except Exception:
                    pass
            self._key = key
            self._window_start = now
            self._count = 1
            self._suppressed = 0
            return True

        self._count += 1
        if self._count <= self.max_per_window:
            return True
        self._suppressed += 1
        return False


def _build_handler(log_file):
    """Create a RotatingFileHandler with the flood-protection filter attached."""
    handler = RotatingFileHandler(
        log_file, maxBytes=max_log_size, backupCount=backup_count
    )
    handler.setFormatter(logging.Formatter('%(asctime)s - %(levelname)s - %(message)s'))
    handler.addFilter(DuplicateRateLimitFilter(max_per_window=5, window_seconds=10.0))
    return handler


logging.basicConfig(
    encoding="utf-8",
    level=logging.INFO,
    handlers=[_build_handler(current_config['LOG_FILE'])],
)

# Quiet the library loggers: pychromecast emits a "Receiver:channel_disconnected"
# INFO line on every reconnect cycle - that noise is what drowned the real log
# history. Keep WARNING+ so genuine errors still surface.
logging.getLogger('pychromecast').setLevel(logging.WARNING)
# zeroconf logs a multi-line traceback (as WARNING) whenever it can't answer an
# mDNS query on an unusable interface (e.g. a VPN link, Errno 126); harmless,
# so only show real errors.
logging.getLogger('zeroconf').setLevel(logging.ERROR)


# Initialize the log
logging.info("====================================")
logging.info("Athan automation script initialized.")


def check_and_reload_config():
    global current_config, last_mtime
    if not os.path.exists(CONFIG_FILE):
        return
    current_mtime = os.stat(CONFIG_FILE).st_mtime
    if current_mtime != last_mtime:
        try:
            new_config, new_last_mtime = load_config()
            if new_config['LOG_FILE'] != current_config['LOG_FILE']:
                setup_logging(new_config['LOG_FILE'])
            current_config = new_config
            last_mtime = new_last_mtime
            logging.info("Configuration reloaded due to file change.")
        except Exception as e:
            logging.error(f"Failed to reload config: {e}")


def setup_logging(log_file):
    """Reconfigure logging with a rotating, flood-protected file handler."""
    for handler in logging.root.handlers[:]:
        logging.root.removeHandler(handler)
    logging.root.setLevel(logging.INFO)
    logging.root.addHandler(_build_handler(log_file))
    logging.getLogger('pychromecast').setLevel(logging.WARNING)
    logging.getLogger('zeroconf').setLevel(logging.ERROR)
    logging.info("Logging reconfigured. Now writing to: " + log_file)


# =============================================================================
# Zeroconf lifecycle
# =============================================================================
def make_zeroconf():
    """Build a Zeroconf instance bound to the configured LAN interface(s).

    Binding to the host's LAN IP keeps mDNS off unusable interfaces (e.g. a VPN
    link that rejects sends with OSError [Errno 126]); those send failures can
    tear down the Zeroconf event loop. Blank -> all interfaces.
    """
    ifaces = [i.strip() for i in current_config.get('ZEROCONF_INTERFACE', '').split(',') if i.strip()]
    if ifaces:
        return Zeroconf(interfaces=ifaces)
    return Zeroconf()


# One process-wide Zeroconf instance. Its event loop must stay running for the
# lifetime of any cast connection (the socket-client worker re-resolves the host
# through it on every reconnect). Created once; never closed during normal
# operation - only on explicit reinit.
zeroconf_instance = make_zeroconf()
logging.info("Zeroconf instance created.")


def zeroconf_is_alive():
    """Return True if the shared Zeroconf instance's event loop is running."""
    loop = getattr(zeroconf_instance, 'loop', None)
    if loop is None:
        return True  # can't determine on this version; reactive guard covers it
    try:
        return loop.is_running()
    except Exception:
        return False


def reinit_zeroconf():
    """Recreate the shared Zeroconf instance if its loop has been stopped."""
    global zeroconf_instance
    try:
        logging.info("Reinitializing Zeroconf instance...")
        try:
            zeroconf_instance.close()
        except Exception as ex:
            logging.error(f"Error closing Zeroconf during reinit: {ex}")
        zeroconf_instance = make_zeroconf()
        logging.info("Zeroconf reinitialized.")
    except Exception as e:
        logging.error(f"Failed to reinitialize Zeroconf: {e}")


def stop_discovery_keep_zeroconf(browser):
    """Stop a CastBrowser's discovery threads WITHOUT closing the shared Zeroconf.

    pychromecast's CastBrowser.stop_discovery() unconditionally calls
    self._zc_browser.zc.close() - closing the Zeroconf even when we passed in a
    shared one, which kills the cast's reconnect path. This mirrors
    stop_discovery() but skips the zc.close(), so the long-lived instance
    survives for the cast's reconnect path.
    """
    zc_browser = getattr(browser, '_zc_browser', None)
    if zc_browser is not None:
        try:
            zc_browser.cancel()  # unregister the mDNS ServiceBrowser (no zc leak)
        except RuntimeError:
            pass  # raised if called from within a service callback
    host_browser = getattr(browser, 'host_browser', None)
    if host_browser is not None:
        try:
            host_browser.stop.set()
            host_browser.join()
        except Exception as e:
            logging.error(f"Error stopping host browser: {e}")


def safe_get_listed_chromecasts(*args, **kwargs):
    """Discover listed chromecasts using the shared Zeroconf instance.

    Passing the long-lived zeroconf_instance means pychromecast does NOT create
    its own throwaway Zeroconf/event loop, so the returned cast's worker thread
    keeps a reference to a loop that stays alive.
    """
    global zeroconf_instance
    if zeroconf_instance is None:
        zeroconf_instance = make_zeroconf()
    return pychromecast.get_listed_chromecasts(
        *args, zeroconf_instance=zeroconf_instance, **kwargs
    )


def run_with_timeout(func, *args, timeout, **kwargs):
    """Run a blocking function with hard timeout protection.

    Deliberately NOT a `with ThreadPoolExecutor()` block: its __exit__ calls
    shutdown(wait=True), which blocks until func returns - so the "timeout"
    only fired once the device came back, possibly hours later. On timeout we
    abandon the worker thread instead.
    """
    executor = ThreadPoolExecutor(max_workers=1)
    future = executor.submit(func, *args, **kwargs)
    try:
        return future.result(timeout=timeout)
    except TimeoutError:
        future.cancel()
        raise TimeoutError(f"{func.__name__} timed out after {timeout}s")
    finally:
        executor.shutdown(wait=False)


def cast_is_healthy(cast):
    """Return True if the Chromecast connection appears healthy."""
    try:
        return cast.socket_client.is_connected and cast.status is not None
    except Exception:
        return False


def disconnect_quietly(cast):
    """Disconnect a cast and stop its socket worker thread, ignoring errors."""
    if not cast.socket_client.is_alive():
        return  # never connected; join() would raise on an unstarted thread
    try:
        cast.disconnect(timeout=10)
    except Exception as e:
        logging.warning(f"Error disconnecting abandoned cast connection: {e}")


def connect_to_chromecast(device_name, max_retries, timeout):
    """Connect to device_name with bounded retries. Never blocks indefinitely.

    Raises ConnectionError if it can't connect - the caller then skips the
    prayer instead of hanging for hours.
    """
    for attempt in range(1, max_retries + 1):
        cast = None
        try:
            if not zeroconf_is_alive():
                logging.info("Zeroconf loop not running; reinitializing before connect.")
                reinit_zeroconf()

            logging.info(f"Connecting to {device_name} (attempt {attempt}/{max_retries})")
            chromecasts, browser = run_with_timeout(
                safe_get_listed_chromecasts,
                friendly_names=[device_name],
                timeout=timeout,
            )
            if not chromecasts:
                stop_discovery_keep_zeroconf(browser)
                logging.warning(f"Device '{device_name}' not found (attempt {attempt}/{max_retries}).")
                time.sleep(retry_delay)
                continue

            cast = chromecasts[0]
            # Stop discovery threads but KEEP the shared Zeroconf alive.
            stop_discovery_keep_zeroconf(browser)
            # Bound the socket connect too; an unbounded cast.wait() can hang for hours.
            # cast.wait() supports a native timeout and raises RequestTimeout
            # when it expires (handled below, which also disconnects the cast).
            cast.wait(timeout=timeout)

            if not cast_is_healthy(cast):
                logging.warning(f"Could not establish a healthy connection to {device_name} "
                                f"within {timeout}s (attempt {attempt}/{max_retries}).")
                disconnect_quietly(cast)
                time.sleep(retry_delay)
                continue

            logging.info(f"Connected to {device_name}.")
            return cast
        except TimeoutError:
            logging.error(f"Connection timeout to {device_name} (attempt {attempt}/{max_retries}).")
        except OSError as e:
            logging.error(f"Network error connecting to {device_name} (attempt {attempt}/{max_retries}): {e}")
        except Exception as e:
            logging.error(f"Connection error to {device_name} (attempt {attempt}/{max_retries}): {e}")
            if "Zeroconf instance loop must be running" in str(e) or "event loop is not running" in str(e):
                logging.error("Detected Zeroconf shut down. Reinitializing Zeroconf...")
                reinit_zeroconf()
        # Never abandon a half-open cast: its socket worker thread would keep
        # reconnecting in the background forever, logging "Error reading from
        # socket" while the script sleeps.
        if cast is not None:
            disconnect_quietly(cast)
        time.sleep(retry_delay)

    raise ConnectionError(f"Failed to connect to {device_name} after {max_retries} attempts")


# =============================================================================
# Media helpers
# =============================================================================
def get_random_athan_file(prayer_name, month=None):
    """Select a random Athan file based on the prayer and month."""
    prayer_name = prayer_name.lower()
    if prayer_name == 'fajr':
        folder, folder_name = current_config['FAJR_FOLDER'], 'fajr'
    elif prayer_name == 'maghrib' and month == 'Ramadan':
        folder, folder_name = current_config['IFTAR_FOLDER'], 'iftar'
    else:
        folder, folder_name = current_config['PRAYER_FOLDER'], 'prayer'

    try:
        files = os.listdir(folder)
        if not files:
            raise FileNotFoundError(f"No files found in {folder}")
        audio_file = random.choice(files)
        logging.info(f"Selected file: {audio_file} for {prayer_name} during {month}")
        return f"{current_config['LIGHTTPD_BASE_URL']}/{folder_name}/{audio_file}"
    except Exception as e:
        logging.error(f"Error selecting Athan file: {e}")
        return None


def get_id3_metadata(file_path):
    """Extract ID3 metadata (title, artist, album) from an MP3 file."""
    try:
        audio = EasyID3(file_path)
        return {
            'title': audio.get('title', ['Unknown Title'])[0],
            'artist': audio.get('artist', ['Unknown Artist'])[0],
            'album': audio.get('album', ['Unknown Album'])[0],
        }
    except Exception as e:
        logging.error(f"Error reading ID3 metadata from {file_path}: {e}")
        return {}


def is_too_late(prayer_name, prayer_time):
    """True (and logs a skip) if we're more than MAX_LATE_SECONDS past prayer_time."""
    if prayer_time is None:
        return False
    late = (datetime.now() - prayer_time).total_seconds()
    if late > current_config['MAX_LATE_SECONDS']:
        logging.warning(
            f"Skipping {prayer_name}: {int(late)}s late "
            f"(> MAX_LATE_SECONDS={current_config['MAX_LATE_SECONDS']}).")
        return True
    return False


def ensure_media_receiver(cast, timeout):
    """Launch the Default Media Receiver and wait until it accepts media commands.

    Instead of firing play_media() at a cold device and hoping, ask the device:
    start_app() blocks until the receiver acknowledges the launch, then we poll
    until the app advertises the media namespace (mc.is_active). This replaces
    the old "PLAY requested but no session is active" first-attempt failures.
    Raises RuntimeError if the receiver isn't ready within `timeout` seconds.
    """
    mc = cast.media_controller
    if cast.status.app_id != APP_MEDIA_RECEIVER or not mc.is_active:
        logging.info(f"Launching Default Media Receiver (current app: {cast.status.display_name}).")
        cast.start_app(APP_MEDIA_RECEIVER, timeout=timeout)

    deadline = time.time() + timeout
    while not mc.is_active:
        if time.time() > deadline:
            raise RuntimeError(f"Default Media Receiver not ready after {timeout}s")
        time.sleep(0.5)
    logging.info("Default Media Receiver is ready.")


# =============================================================================
# Interruption handling
# -----------------------------------------------------------------------------
# When something else casts to a group that includes our speaker (e.g. a home
# automation doorbell chime sent to "All speakers"), our session on the speaker
# simply ends. Polling with mc.update_status() would silently relaunch the
# receiver on a speaker whose app has gone - cutting the other cast off - so we
# only read pushed status, let the other cast finish, and resume the athan
# where it stopped.
# The other cast's playback state lives on the group that cast it (members
# report UNKNOWN), so we also watch every group that shares our speaker.
# =============================================================================
ACTIVE_PLAYER_STATES = ('PLAYING', 'BUFFERING')
INTERRUPTION_TIMEOUT = 180  # give up resuming if the speaker stays busy this long
FREE_SECONDS = 5            # speaker must be quiet this long before we resume


class _MultizoneReady:
    """Listener that flags when a group's member list has arrived."""
    def __init__(self):
        self.event = threading.Event()
    def multizone_member_added(self, group_uuid): pass
    def multizone_member_removed(self, group_uuid): pass
    def multizone_status_received(self): self.event.set()


def get_group_members(cast, timeout=5):
    """Return the set of member device ids of a group cast (empty if not a group)."""
    if cast.cast_info.cast_type != 'group':
        return set()
    mz = MultizoneController(cast.uuid)
    ready = _MultizoneReady()
    mz.register_listener(ready)
    cast.register_handler(mz)
    mz.update_members()
    if not ready.event.wait(timeout):
        logging.warning(f"Could not read the member list of group {cast.name}.")
    cast.unregister_handler(mz)
    return set(mz.members)


def is_our_session(cast, audio_url):
    """True if the receiver on `cast` is holding our audio. Reads pushed status only:
    never call mc.update_status() here, it launches an app on an idle speaker."""
    try:
        mc = cast.media_controller
        return (cast.status is not None and cast.status.app_id == APP_MEDIA_RECEIVER
                and mc.is_active and mc.status.content_id == audio_url)
    except Exception:
        return False


def find_sharing_groups(cast):
    """Connect to every other group that includes our speaker(s), e.g. All speakers."""
    ours = get_group_members(cast) or {str(cast.uuid)}
    groups = []
    try:
        found, browser = run_with_timeout(
            pychromecast.get_chromecasts, zeroconf_instance=zeroconf_instance,
            timeout=current_config['TIMEOUT'])
        stop_discovery_keep_zeroconf(browser)
    except Exception as e:
        logging.warning(f"Discovery of groups sharing {cast.name} failed: {e}")
        return groups
    for c in found:
        if c.cast_info.cast_type != 'group' or c.uuid == cast.uuid:
            continue
        try:
            c.wait(timeout=10)
            if get_group_members(c) & ours:
                groups.append(c)
                continue
        except Exception as e:
            logging.warning(f"Could not check group {c.name}: {e}")
        disconnect_quietly(c)
    logging.info(f"Groups sharing {cast.name}: {[g.name for g in groups]}")
    return groups


def wait_until_free(cast, audio_url, timeout):
    """Wait for another cast on our speaker to finish. True if free within timeout."""
    groups = find_sharing_groups(cast)
    try:
        deadline = time.time() + timeout
        free_since = None
        while time.time() < deadline:
            busy = False
            for c in [cast] + groups:
                st = c.media_controller.status
                if st.player_state in ACTIVE_PLAYER_STATES and st.content_id != audio_url:
                    busy = True
                    break
            if busy:
                free_since = None
            elif free_since is None:
                free_since = time.time()
            elif time.time() - free_since >= FREE_SECONDS:
                return True
            time.sleep(1)
        return False
    finally:
        for g in groups:
            disconnect_quietly(g)


def resume_audio(cast, audio_url, media_metadata, position, timeout=20):
    """Relaunch the receiver and continue our audio from `position`."""
    mc = cast.media_controller
    ensure_media_receiver(cast, timeout)
    mc.play_media(audio_url, 'audio/mp3', current_time=position, metadata=media_metadata)
    deadline = time.time() + timeout
    while time.time() < deadline:
        if is_our_session(cast, audio_url) and mc.status.player_state in ACTIVE_PLAYER_STATES:
            return
        time.sleep(0.5)
    raise RuntimeError(f"audio did not resume within {timeout}s")


def cast_announcement_and_athan(audio_url, device_name, prayer_name, prayer_time=None):
    """
    Connect (bounded), cast the Athan, wait for playback, then always disconnect.

    The shared Zeroconf is NEVER closed here - only cast.disconnect() runs in the
    finally block, so the cast's reconnect path keeps a live event loop.
    """
    cast = None
    try:
        # If we're already far past the scheduled time, don't play a stale athan.
        if is_too_late(prayer_name, prayer_time):
            return

        local_audio_path = audio_url.replace(current_config['LIGHTTPD_BASE_URL'], "/var/www/html/athan")
        metadata = get_id3_metadata(local_audio_path)
        thumbnail_url = current_config['IFTAR_ART_URL'] if "iftar" in audio_url else current_config['ATHAN_ART_URL']

        # Bounded connect - raises ConnectionError instead of hanging forever.
        cast = connect_to_chromecast(device_name, current_config['MAX_RETRIES'], current_config['TIMEOUT'])

        # Check again: connecting can take minutes, and an Isha at 2 AM is worse
        # than a skipped one.
        if is_too_late(prayer_name, prayer_time):
            return

        mc = cast.media_controller
        logging.info(f"Active app is {cast.status.app_id}: {cast.status.display_name}.")

        # Stop a foreign streaming app if one is active.
        if cast.status.app_id in ['CC32E753', '705D30C6']:
            logging.info(f"Active streaming app {cast.status.app_id} found, attempting to stop app.")
            cast.quit_app()
            timeout = 30
            start_time = time.time()
            while time.time() - start_time < timeout:
                if cast.status.app_id is None:
                    logging.info("Chromecast is now idle.")
                    break
                time.sleep(1)
            else:
                logging.warning("Chromecast did not become idle within timeout. Proceeding anyway.")
        else:
            logging.info("Chromecast speaker is idle.")

        volume_level = current_config['FAJR_VOLUME_LEVEL'] if prayer_name.lower() == "fajr" else current_config['ATHAN_VOLUME_LEVEL']
        cast.set_volume(volume_level)
        logging.info(f"Volume set to {volume_level * 100}% for {prayer_name}.")

        media_metadata = {
            'metadataType': 3,
            'title': metadata.get('title', 'Athan'),
            'artist': metadata.get('artist', 'Unknown Reciter'),
            'album': metadata.get('album', 'Islamic Prayers'),
            'images': [{'url': thumbnail_url}],
        }

        # Play with retries. Each attempt first confirms the media receiver is
        # up, then waits for the device to acknowledge the LOAD and open a media
        # session. autoplay (the default) starts playback, so no separate play().
        retries = 3
        for attempt in range(retries):
            try:
                ensure_media_receiver(cast, timeout=20)
                load_response = WaitResponse(20, "load media")
                mc.play_media(audio_url, 'audio/mp3', metadata=media_metadata,
                              callback_function=load_response.callback)
                load_response.wait_response()
                if not mc.session_active_event.wait(timeout=20):
                    raise RuntimeError("Media session did not become active within 20s")
                logging.info(f"Playing Athan from URL: {audio_url}")
                break
            except Exception as e:
                logging.error(f"Attempt {attempt + 1} to play media failed: {e}")
                if attempt < retries - 1:
                    logging.info("Retrying playback...")
                    time.sleep(5)
                else:
                    logging.error(f"Failed to play media after {attempt + 1} attempts.")
                    return

        # Wait for playback to finish, with a hard cap so a stuck stream can't
        # spin. Status is pushed by the speaker, so we only read it.
        logging.info("Waiting for playback to complete.")
        playback_timeout = 900  # 15 min hard cap (allows for interruptions)
        wait_start = time.time()
        last_pos = 0.0
        paused_since = None
        gone_since = None
        interruptions = 0
        while time.time() - wait_start < playback_timeout:
            time.sleep(1)
            if not cast_is_healthy(cast):
                continue  # pychromecast is reconnecting; the hard cap bounds this

            st = mc.status
            ours = is_our_session(cast, audio_url)
            if ours and not (st.player_state == 'IDLE' and st.idle_reason == 'INTERRUPTED'):
                gone_since = None
                if st.player_state in ACTIVE_PLAYER_STATES:
                    paused_since = None
                    last_pos = st.adjusted_current_time or last_pos
                elif st.player_state == 'PAUSED':
                    # "Hey Google, pause/stop" (identical on the wire): stop.
                    paused_since = paused_since or time.time()
                    if time.time() - paused_since >= 10:
                        logging.info("Athan paused/stopped at the speaker.")
                        break
                elif st.player_state == 'IDLE':
                    logging.info(f"Chromecast speaker status is now IDLE ({st.idle_reason}).")
                    logging.info("Playback completed.")
                    break
                continue

            # Our session is gone or was replaced: confirm it for 2s so a
            # transient status blip can't make us restart the athan.
            gone_since = gone_since or time.time()
            if time.time() - gone_since < 2:
                continue
            gone_since = None
            interruptions += 1
            if interruptions > 3:
                logging.warning("Athan interrupted too many times; not resuming.")
                break
            logging.info(f"Athan interrupted by another cast at {last_pos:.0f}s "
                         f"(e.g. doorbell); waiting for it to finish.")
            if not wait_until_free(cast, audio_url, INTERRUPTION_TIMEOUT):
                logging.warning(f"Speaker still busy after {INTERRUPTION_TIMEOUT}s; not resuming the athan.")
                break
            logging.info(f"Speaker free again; resuming athan at {last_pos:.0f}s.")
            try:
                resume_audio(cast, audio_url, media_metadata, last_pos)
            except Exception as e:
                logging.error(f"Could not resume the athan: {e}")
                break
        else:
            logging.warning("Playback wait exceeded timeout. Proceeding to disconnect.")

        # Only close the receiver if it's still ours - never someone else's
        # (e.g. a receiver left open by another cast that interrupted us).
        if is_our_session(cast, audio_url):
            cast.quit_app()
    except ConnectionError as ce:
        logging.error(f"{ce}. Skipping {prayer_name}.")
    except Exception as e:
        logging.error(f"Error during casting: {e}")
    finally:
        # Disconnect the cast, but DO NOT close the shared Zeroconf instance.
        if cast is not None:
            try:
                cast.disconnect(timeout=10)
                logging.info(f"Disconnected from {device_name}")
            except Exception as e:
                logging.error(f"Disconnection error: {e}")


# =============================================================================
# Scheduling
# =============================================================================
def get_next_prayer_time(file_path):
    """Read the next upcoming prayer time from the CSV file."""
    try:
        df = pd.read_csv(file_path, parse_dates=["Time and Date"])
        now = datetime.now()
        future_prayer_times = df[df["Time and Date"] > now]
        if not future_prayer_times.empty:
            next_prayer = future_prayer_times.iloc[0]
            logging.info(f"Next prayer: {next_prayer['Prayer Name']} at {next_prayer['Time and Date']} during {next_prayer['Month']}")
            return next_prayer["Prayer Name"], next_prayer["Time and Date"], next_prayer["Month"]
        logging.warning("No upcoming prayer times found.")
        return None, None, None
    except Exception as e:
        logging.error(f"Error reading the CSV file: {e}")
        return None, None, None


def wait_until_next_prayer(prayer_time, prayer_name, month):
    """Wait until the prayer time, adjusting earlier for Ramadan Iftar."""
    if month == 'Ramadan' and prayer_name.lower() == 'maghrib':
        target = prayer_time - timedelta(minutes=2, seconds=30)
        logging.info(f"Waiting {target - datetime.now()} for Iftar announcement.")
    else:
        target = prayer_time - timedelta(seconds=3)
        logging.info(f"Waiting {target - datetime.now()} until {prayer_name}.")

    if target <= datetime.now():
        logging.warning(f"Prayer time for {prayer_name} has already passed.")
        return

    # Sleep in short chunks, re-checking the wall clock each time. A single
    # long time.sleep() runs on the monotonic clock, so if NTP corrects the
    # wall clock mid-wait (e.g. right after a reboot) we'd wake at the wrong
    # time. Re-checking also keeps prayers on time across DST changes.
    while True:
        remaining = (target - datetime.now()).total_seconds()
        if remaining <= 0:
            return
        time.sleep(min(remaining, SLEEP_CHUNK_SECONDS))


def is_clock_synchronized():
    """Ask systemd whether the system clock is NTP-synchronized."""
    try:
        out = subprocess.run(
            ['timedatectl', 'show', '--property=NTPSynchronized', '--value'],
            capture_output=True, text=True, timeout=10,
        ).stdout.strip()
        return out == 'yes'
    except Exception as e:
        logging.warning(f"Could not query clock sync status: {e}")
        return None


def wait_for_clock_sync(max_wait):
    """At startup, wait (bounded) for NTP sync before scheduling anything.

    After a reboot the Pi's clock can be off until NTP catches up, and picking
    the "next prayer" from a wrong clock schedules the wrong one. Bounded so an
    internet outage doesn't stop the athan entirely - we proceed on the local
    clock and the chunked sleep picks up any later correction.
    """
    status = is_clock_synchronized()
    if status is not False:
        if status:
            logging.info("System clock is NTP-synchronized.")
        return
    logging.info(f"System clock not yet synchronized; waiting up to {max_wait}s for NTP...")
    deadline = time.monotonic() + max_wait
    while time.monotonic() < deadline:
        time.sleep(5)
        if is_clock_synchronized():
            logging.info(f"System clock synchronized. Current time: {datetime.now()}")
            return
    logging.warning(f"Clock still not synchronized after {max_wait}s; proceeding with local time.")


wait_for_clock_sync(current_config['CLOCK_SYNC_MAX_WAIT'])


while True:
    try:
        check_and_reload_config()
        prayer_name, next_prayer_time, month = get_next_prayer_time(current_config['PRAYER_TIMES_FILE'])
        if next_prayer_time is not None:
            wait_until_next_prayer(next_prayer_time, prayer_name, month)
            check_and_reload_config()
            logging.info("Waking up...")
            device_name = current_config['IFTAR_DEVICE'] if month == 'Ramadan' and prayer_name.lower() == 'maghrib' else current_config['ATHAN_DEVICE']
            audio_url = get_random_athan_file(prayer_name, month)

            if not audio_url:
                logging.error("No audio file available. Skipping this prayer.")
                continue

            # Convert pandas Timestamp -> datetime for the lateness guard.
            pt = next_prayer_time.to_pydatetime() if hasattr(next_prayer_time, "to_pydatetime") else next_prayer_time
            cast_announcement_and_athan(audio_url, device_name, prayer_name, prayer_time=pt)

            pause_time = 180
            logging.info(f"Waiting for {pause_time / 60} minutes..")
            time.sleep(pause_time)
            logging.info("Resuming...")
        else:
            logging.warning("No more prayer times available. Exiting...")
            break
    except pychromecast.error.ChromecastConnectionError as cce:
        logging.error(f"Chromecast connection lost: {cce}. Retrying in 60 seconds...")
        time.sleep(60)
    except Exception as e:
        logging.error(f"Unhandled error: {e}. Retrying in 60 seconds...")
        time.sleep(60)
