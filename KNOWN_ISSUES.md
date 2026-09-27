# Known Issues

Issues found during a code review on 2026-09-27. They are numbered in the order they should be fixed. Tick an item off and reference the commit once it is fixed.

Line numbers refer to the code as of commit `15f1461`.

## High: missed or wrong-time Athans

- [ ] **1. Fajr can play an hour early or be skipped on daylight-saving days** — `athan_automation.py:531`
  The script sleeps for the whole wait in one `time.sleep()`, but prayer times are local clock times. When the clocks go back, Fajr plays an hour early (the lateness guard only checks for late). When they go forward, it wakes an hour late and skips Fajr. The same applies to a Raspberry Pi at boot, before its clock syncs over the network.
  *Fix:* sleep in short chunks (e.g. 30 s) and re-check `datetime.now()` each time.

- [ ] **2. Generated prayer times are an hour off on each clock-change day** — `tools/prayer_times_python.py:152`
  The timezone offset is read at midnight, but clocks change at about 2 AM, so all five prayers that day use the old offset.
  *Fix:* read the offset at noon. (`datetime.utcfromtimestamp` is also deprecated in Python 3.12.)

- [ ] **3. Connection timeouts don't actually time out** — `athan_automation.py:276`
  `run_with_timeout` uses `ThreadPoolExecutor` as a context manager, whose exit waits for the task to finish. A 1 s timeout on a 4 s task returned after 4 s. An unreachable speaker can therefore block `cast.wait()` for hours and later prayers are missed.
  *Fix:* pass the timeout to `cast.wait(timeout=...)`, or shut the pool down with `wait=False`.

## High: `setup.sh` breaks on common setups

- [ ] **4. Setup aborts if lighttpd or Apache is already running** — `setup.sh:335`
  `configure_webserver` returns 1 for lighttpd/Apache (and when `nginx -t` fails). Under `set -e` that ends the script, so the systemd service and prayer times file are never created.

- [ ] **5. Setup fails on Fedora when system updates are pending** — `setup.sh:55`
  `dnf check-update` exits with code 100 when updates are available, which aborts the script under `set -e`.

- [ ] **6. On Fedora, speakers can't download the audio**
  firewalld blocks port 80 by default and setup never opens it.
  *Fix:* run `firewall-cmd --permanent --add-service=http && firewall-cmd --reload` when firewalld is active.

## Medium

- [ ] **7. Filenames with spaces break playback** — `athan_automation.py:369`
  The file name is put into the URL without percent-encoding. Any file in the folder can also be picked, including non-MP3 files.

- [ ] **8. An empty Iftar folder makes the script spin at full CPU for 2.5 minutes** — `athan_automation.py:548`
  When no audio file is found, the loop immediately picks the same prayer again. During Ramadan it wakes 2.5 minutes before Maghrib, so it loops until Maghrib passes.

- [ ] **9. When the prayer times file runs out, the script exits** — `athan_automation.py:561`
  systemd then restarts it every 10 seconds indefinitely, and no Athan plays.
  *Fix:* sleep and re-check the file (e.g. hourly) instead of exiting.

- [ ] **10. Setup deletes nginx's default site** — `setup.sh:160`
  On Debian it removes `sites-enabled/default` even when nginx was already serving something else.

- [ ] **11. A failed connection attempt leaves discovery running** — `athan_automation.py:308`
  If the connect times out, the browser is never stopped, so each failed attempt leaks a discovery thread.

## Low

- [ ] **12. Speaker volume is never restored** — after the Athan, whatever plays next on that speaker uses the Athan volume.

- [ ] **13. Setup writes the service file to a fixed path in `/tmp`** — `setup.sh:354`
  It is then copied into place with sudo. Writing it directly with `sudo tee` is safer.

- [ ] **14. ID3 lookup ignores the configured folders** — `athan_automation.py:407`
  The local path is built from a hard-coded `/var/www/html/athan`, and the artwork is chosen by checking whether "iftar" appears anywhere in the URL.

- [ ] **15. A missing config file crashes the script at startup** — `athan_automation.py:47`
  The log says defaults will be used, but `prayer_times_file` and `log_file` have no defaults.

- [ ] **16. Setup must be run from the repository folder**
  Otherwise it silently skips installing the main script and the tools.
