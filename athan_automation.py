import pychromecast
import pandas as pd
import time
import logging
from datetime import datetime, timedelta
import os
import random
import sys
from logging.handlers import RotatingFileHandler
import zeroconf
from mutagen.easyid3 import EasyID3  # New import for MP3 metadata
import configparser

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
    }  # ✅ Added missing commas at the end of each line

    # Log a warning if the prayer times file is missing
    if not os.path.exists(settings['PRAYER_TIMES_FILE']):
        logging.warning(f"Prayer times file not found: {settings['PRAYER_TIMES_FILE']}.")

    last_mtime = os.stat(CONFIG_FILE).st_mtime if os.path.exists(CONFIG_FILE) else None
    return settings, last_mtime


current_config, last_mtime = load_config()

max_retries = 3 # discovery retries
retry_delay = 5  # seconds between retries

# ========================
# Logging Configuration
# ========================
# (We use the LOG_FILE from the config when first loaded.)
current_config, last_mtime = load_config()
max_log_size = 5 * 1024 * 1024  # 5 MB
backup_count = 3  # Number of log backups to keep

logging.basicConfig(
    format='%(asctime)s - %(levelname)s - %(message)s',
    encoding="utf-8",
    level=logging.INFO,
    handlers=[
        RotatingFileHandler(
            current_config['LOG_FILE'], maxBytes=max_log_size, backupCount=backup_count
        )
    ],
)

def check_and_reload_config():
    global current_config, last_mtime
    if not os.path.exists(CONFIG_FILE):
        return
    current_mtime = os.stat(CONFIG_FILE).st_mtime
    if current_mtime != last_mtime:
        try:
            new_config, new_last_mtime = load_config()
            # Check if log file changed
            if new_config['LOG_FILE'] != current_config['LOG_FILE']:
                setup_logging(new_config['LOG_FILE'])
            current_config = new_config
            last_mtime = new_last_mtime
            logging.info("Configuration reloaded due to file change.")
        except Exception as e:
            logging.error(f"Failed to reload config: {e}")

def setup_logging(log_file):
    """
    Configures logging with a rotating file handler.
    This function should be called whenever the config file is reloaded.
    """
    max_log_size = 5 * 1024 * 1024  # 5 MB
    backup_count = 3  # Keep 3 backup logs

    # Remove old handlers (to avoid duplicate log entries)
    for handler in logging.root.handlers[:]:
        logging.root.removeHandler(handler)

    # Set up logging again
    logging.basicConfig(
        format="%(asctime)s - %(levelname)s - %(message)s",
        encoding="utf-8",
        level=logging.INFO,
        handlers=[
            RotatingFileHandler(log_file, maxBytes=max_log_size, backupCount=backup_count)
        ],
    )

    logging.info("Logging reconfigured. Now writing to: " + log_file)



logging.info("====================================")
logging.info("Athan automation script initialized.")

def get_random_athan_file(prayer_name, month=None):
    """
    Select a random Athan file based on the prayer and month.
    """
    prayer_name = prayer_name.lower()
    folder, folder_name = None, None
    
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
    """
    Extract ID3 metadata (title, artist, album) from the given MP3 file.
    Returns a dictionary with keys 'title', 'artist', 'album'.
    """
    try:
        audio = EasyID3(file_path)
        title = audio.get('title', ['Unknown Title'])[0]
        artist = audio.get('artist', ['Unknown Artist'])[0]
        album = audio.get('album', ['Unknown Album'])[0]
        return {'title': title, 'artist': artist, 'album': album}
    except Exception as e:
        logging.error(f"Error reading ID3 metadata from {file_path}: {e}")
        return {}


def cast_announcement_and_athan(audio_url, device_name, prayer_name):
    """
    Casts the Athan to the specified device and waits until playback finishes.
    """
    try:
        
        # Extract metadata from the MP3 file
        local_audio_path = audio_url.replace(current_config['LIGHTTPD_BASE_URL'], "/var/www/html/athan")  # Convert URL to local path
        metadata = get_id3_metadata(local_audio_path)
        
        if "iftar" in audio_url:
            thumbnail_url = current_config['IFTAR_ART_URL']
        else:
            thumbnail_url = current_config['ATHAN_ART_URL'] 
            

        chromecasts = None
        browser = None

        # Retry loop for Chromecast discovery
        for attempt in range(max_retries):
            try:
                # Initialize Zeroconf
                zconf = zeroconf.Zeroconf()
                chromecasts, browser = pychromecast.get_listed_chromecasts(friendly_names=[device_name], zeroconf_instance=zconf)
                if chromecasts:
                    break
                logging.warning(f"Chromecast discovery attempt {attempt+1} failed - device not found")
            except Exception as e:
                logging.error(f"Discovery attempt {attempt+1} failed with error: {e}")

            if attempt < max_retries - 1:
                logging.info(f"Retrying discovery in {retry_delay} seconds...")
                time.sleep(retry_delay)
        else:
            raise ConnectionError(f"No Chromecast with name {device_name} discovered after {max_retries} attempts.") 
        cast = chromecasts[0]
        cast.wait()
        logging.info(f"Connected to {device_name}.")
        
        browser.stop_discovery()
        zconf.close()
        mc = cast.media_controller
        logging.info(f"Active app is {cast.status.app_id}: {cast.status.display_name}.")

        # Stop the current app if any is active
        if cast.status.app_id in ['CC32E753', '705D30C6']:
            logging.info(f"Active streaming app {cast.status.app_id} found, attempting to stop app.")
            cast.quit_app()
            
            # Wait until the Chromecast is ready
            timeout = 30
            start_time = time.time()
            while time.time() - start_time < timeout:
                if cast.status.app_id is None:  # Chromecast is idle
                    logging.info("Chromecast is now idle.")
                    break
                time.sleep(1)
            else:
                logging.warning("Chromecast did not become idle within timeout. Proceeding anyway.")
        else:
            logging.info("Chromecast speaker is  idle.")

        # Set volume
        volume_level = current_config['FAJR_VOLUME_LEVEL'] if prayer_name.lower() == "fajr" else current_config['ATHAN_VOLUME_LEVEL']
        cast.set_volume(volume_level)
        logging.info(f"Volume set to {volume_level * 100}% for {prayer_name}.")
        
        # Media metadata
        media_metadata = {
            'metadataType': 3,  # Generic media type
            'title': metadata.get('title', 'Athan'),
            'artist': metadata.get('artist', 'Unknown Reciter'),
            'album': metadata.get('album', 'Islamic Prayers'),
            'images': [{'url': thumbnail_url}]
        }

        # Play the media
        retries = 3  # Retry up to 3 times if playback fails
        for attempt in range(retries):
            try:
                mc.play_media(audio_url, 'audio/mp3', metadata=media_metadata)
                mc.block_until_active(timeout=20)
                logging.info(f"Playing Athan from URL: {audio_url}")
                mc.play()
                break
            except Exception as e:
                logging.error(f"Attempt {attempt + 1} to play media failed: {e}")
                if attempt < retries - 1:
                    logging.info("Retrying playback...")
                    time.sleep(5)
                else:
                    logging.error(f"Failed to play media after {attempt + 1} attempts.")
                    return
        
        # Wait for playback to finish
        logging.info("Waiting for playback to complete.")
        state_count = 0
        while True:
            time.sleep(5)
            mc.update_status()  # Refresh the media status
            if mc.status.player_state not in ['PLAYING', 'BUFFERING']:  # Playback finished
                logging.info(f"Chromecast speaker status is now {mc.status.player_state}")
                state_count = state_count + 1
                if state_count >= 2:
                    logging.info("Playback completed.")
                    break
        cast.wait(timeout=10)
        # Quit the app and disconnect
        if cast.status.display_name == "Default Media Receiver":
            cast.quit_app()
        # logging.info("Stopped the streaming app.")
        cast.wait(timeout=10)
        cast.disconnect()
        logging.info(f"Disconnected from {device_name}")
    except Exception as e:
        logging.error(f"Error during casting: {e}")


def get_next_prayer_time(file_path):
    """
    Reads the next prayer time from the CSV file.
    """
    try:
        df = pd.read_csv(file_path, parse_dates=["Time and Date"])
        now = datetime.now()
        future_prayer_times = df[df["Time and Date"] > now]

        if not future_prayer_times.empty:
            next_prayer = future_prayer_times.iloc[0]
            logging.info(f"Next prayer: {next_prayer['Prayer Name']} at {next_prayer['Time and Date']} during {next_prayer['Month']}")
            return next_prayer["Prayer Name"], next_prayer["Time and Date"], next_prayer["Month"]
        else:
            logging.warning("No upcoming prayer times found.")
            return None, None, None
    except Exception as e:
        logging.error(f"Error reading the CSV file: {e}")
        return None, None, None

def wait_until_next_prayer(prayer_time, prayer_name, month):
    """
    Waits until the specified prayer time, adjusting for Iftar announcements if needed.
    """
    if month == 'Ramadan' and prayer_name.lower() == 'maghrib':
        wait_time = (prayer_time - timedelta(minutes=2, seconds=30)) - datetime.now()
        logging.info(f"Waiting {wait_time} for Iftar announcement.")
    else:
        wait_time = (prayer_time - timedelta(seconds=3)) - datetime.now()
        logging.info(f"Waiting {wait_time} until {prayer_name}.")

    if wait_time.total_seconds() > 0:
        time.sleep(wait_time.total_seconds())
    else:
        logging.warning(f"Prayer time for {prayer_name} has already passed.")

while True:
    try:

        check_and_reload_config()
        prayer_name, next_prayer_time, month = get_next_prayer_time(current_config['PRAYER_TIMES_FILE'])
        if next_prayer_time:
            wait_until_next_prayer(next_prayer_time, prayer_name, month)
            check_and_reload_config()
            logging.info("Waking up...")
            device_name = current_config['IFTAR_DEVICE'] if month == 'Ramadan' and prayer_name.lower() == 'maghrib' else current_config['ATHAN_DEVICE']
            audio_url = get_random_athan_file(prayer_name, month)
            
            if not audio_url:
                logging.error("No audio file available. Skipping this prayer.")
                continue
            
            # wait_until_next_prayer(next_prayer_time, prayer_name, month)
            # Initialize Zeroconf for device discovery
            # zconf = zeroconf.Zeroconf()
            cast_announcement_and_athan(audio_url, device_name, prayer_name)
            
            # Wait for the prayer time to pass before reading the CSV file again
            pause_time = 180
            logging.info(f"Waiting for {pause_time / 60} minutes..")
            time.sleep(pause_time)
            logging.info(f"Resuming...")
        else:
            logging.warning("No more prayer times available. Exiting...")
            break
    except pychromecast.error.ChromecastConnectionError as cce:
        logging.error(f"Chromecast connection lost: {cce}. Retrying in 60 seconds...")
        time.sleep(60)
    except Exception as e:
        logging.error(f"Unhandled error: {e}. Retrying in 60 seconds...")
        time.sleep(60)
