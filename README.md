# Athan Automation for Chromecast

Automatically play the Islamic call to prayer (Athan) on your Chromecast devices at the correct prayer times. This Python script reads prayer times from a CSV file and broadcasts Athan recitations to your Google Cast-enabled speakers or displays.

## Features

- Automatic Athan playback at all five daily prayer times
- Random selection from multiple Athan audio files
- Special Ramadan support with Iftar announcements (the announcement is hard-coded to start 2.5 minutes before Maghrib to allow for an anticipatory tune)
- Supports multiple Chromecast devices as well as speaker groups
- Configurable volume levels (separate settings for Fajr and other prayers)
- Displays beautiful Islamic artwork during playback
- ID3 metadata support (shows reciter name, title, etc.)
- Hot-reload configuration without restarting
- Comprehensive logging with rotation
- Automatic retry and error recovery
- Built-in prayer times calculator
- Supports Debian and RHEL/Fedora based distributions

## Prerequisites

- Raspberry Pi or Linux server (can run 24/7) running any Debian or Fedora based distribution
- Google Chromecast devices on the same network
- Web server (lighttpd, Apache, or nginx) to serve audio files (the setup script installs and configures nginx if none is running)

## Installation

### 1. Clone the Repository

```bash
git clone https://github.com/nofaily/athan-automation.git
cd athan-automation
```

### 2. Run the Setup Script

```bash
chmod +x setup.sh
./setup.sh
```

The setup script will:
- Create necessary directories
- Set up Python virtual environment
- Install all dependencies
- Create configuration file
- Set up systemd service

### 3. Add Your Audio Files

Place your Athan MP3 files in the appropriate directories:
- `/var/www/html/athan/fajr/` - Fajr Athan files
- `/var/www/html/athan/prayer/` - Regular prayer Athan files
- `/var/www/html/athan/iftar/` - Ramadan Iftar announcement files

#### For Fedora Linux
- After you copy your files to the appropriate folder, you need to restore the SELinux file labels so the web server can serve them correctly.

```bash
# This ensures Nginx (httpd_t) is allowed to read everything inside.
sudo restorecon -Rv /var/www/html/athan/

# Re-test the service status to confirm it's running (optional but good practice)
sudo systemctl status nginx
```

**Note:** Make sure your MP3 files have proper ID3 tags (title, artist, album) for best display on Chromecast devices.

### 4. Add Artwork (Optional)

Place artwork images in `/var/www/html/athan/`:
- `Mohamed_Ali_Mosque.jpg` - Displayed during regular prayers
- `Iftar.jpg` - Displayed during Ramadan Iftar

#### For Fedora Linux
- Again, make sure to restore the SELinux file labels

```bash
# This ensures Nginx (httpd_t) is allowed to read everything inside.
sudo restorecon -Rv /var/www/html/athan/

# Re-test the service status to confirm it's running (optional but good practice)
sudo systemctl status nginx
```

### 5. Configure Your Settings

Edit the configuration file:

```bash
nano /etc/athan-automation/config.ini
```

Update the following settings:
- `lighttpd_base_url` - Your server's IP address or URL (doesn't have to be lighttpd; any web server works as long as it serves `/var/www/html/athan`)
- `athan_art_url` / `iftar_art_url` - Update the host in these URLs to match your server
- `athan_device` - Name of your Chromecast device
- `iftar_device` - Device for Ramadan announcements
- Volume levels as preferred

### 6. Generate Prayer Times

The project includes a prayer times calculator that will automatically run during setup. You can rerun it to generate your prayer schedule as needed:

```bash
cd /usr/local/share/athan-automation/tools
./prayer_times_shell.sh
```

Follow the prompts to:
- Enter your location coordinates (latitude/longitude) (you can get those from Google Maps)
- Select calculation method (MWL, ISNA, Karachi, etc.) (if you're unsure, see the default prayer calculation settings on your Athan app)
- Choose Asr method (Shafi'i or Hanafi) (if you're unsure, see your Athan app)
- Specify date range

The script will generate `prayer_times.csv` in a temporary directory and move the file to the correct location at `/var/lib/athan-automation/prayer_times.csv`

**Alternative:** You can also generate prayer times from:
- [IslamicFinder.org](https://www.islamicfinder.org/)
- [Adhan API](https://aladhan.com/prayer-times-api)

### 7. Enable and Start the Service

```bash
sudo systemctl enable athan-automation.service
sudo systemctl start athan-automation.service
```

## Linux File System Conventions

This project follows the Filesystem Hierarchy Standard (FHS):

```
/etc/athan-automation/          # Configuration files
└── config.ini                  # Main configuration

/usr/local/bin/                 # Executable script
└── athan-automation            # Main script (copy of athan_automation.py)

/var/lib/athan-automation/      # Application data
└── prayer_times.csv            # Prayer times schedule

/var/www/html/                  # Web server files
└── athan/                      # Audio files and artwork
    ├── fajr/                   # Fajr audio files
    ├── prayer/                 # Regular prayer audio files
    ├── iftar/                  # Iftar audio files
    ├── Mohamed_Ali_Mosque.jpg  # Prayer artwork
    └── Iftar.jpg               # Iftar artwork

/var/log/athan-automation/      # Log files
└── athan.log                   # Application logs

/usr/local/share/athan-automation/  # Shared resources
├── venv/                       # Python virtual environment
└── tools/                      # Prayer times calculator
    ├── prayer_times_python.py
    └── prayer_times_shell.sh
```

## Configuration

### Main Configuration File

The `/etc/athan-automation/config.ini` file contains all settings:

```ini
[DEFAULT]
fajr_folder = /var/www/html/athan/fajr
prayer_folder = /var/www/html/athan/prayer
iftar_folder = /var/www/html/athan/iftar
prayer_times_file = /var/lib/athan-automation/prayer_times.csv
lighttpd_base_url = http://raspberry.pi/html/athan
athan_art_url = http://raspberry.pi/html/athan/Mohamed_Ali_Mosque.jpg
iftar_art_url = http://raspberry.pi/html/athan/Iftar.jpg
athan_device = Kitchen Display
iftar_device = All speakers
log_file = /var/log/athan-automation/athan.log
athan_volume_level = 0.4
fajr_volume_level = 0.2
zeroconf_interface =
max_retries = 3
timeout = 30
max_late_seconds = 600
clock_sync_max_wait = 300
```

### Configuration Options

- **fajr_folder** - Directory containing Fajr Athan files
- **prayer_folder** - Directory containing regular prayer Athan files
- **iftar_folder** - Directory containing Ramadan Iftar files
- **prayer_times_file** - Path to CSV file with prayer times
- **lighttpd_base_url** - Base URL where audio files are served
- **athan_art_url** - Image displayed during regular prayers
- **iftar_art_url** - Image displayed during Iftar
- **athan_device** - Chromecast device name for regular prayers
- **iftar_device** - Chromecast device name for Iftar (can be group)
- **log_file** - Path to log file
- **athan_volume_level** - Volume for regular prayers (0.0 to 1.0)
- **fajr_volume_level** - Volume for Fajr prayer (0.0 to 1.0)
- **zeroconf_interface** - LAN IP(s) to use for Chromecast discovery, comma-separated; blank uses all interfaces. Set this if a VPN or other interface causes mDNS errors
- **max_retries** - Chromecast connection attempts before skipping a prayer
- **timeout** - Seconds allowed per connection attempt
- **max_late_seconds** - Skip the Athan if the speaker is only reached this many seconds after the prayer time
- **clock_sync_max_wait** - At startup, seconds to wait for the clock to sync over NTP before scheduling; after that it proceeds on the local clock

## Usage

### Service Management

```bash
# Check status
sudo systemctl status athan-automation.service

# View logs
sudo journalctl -u athan-automation.service -f

# Restart service
sudo systemctl restart athan-automation.service

# Stop service
sudo systemctl stop athan-automation.service
```

### View Application Logs

```bash
sudo tail -f /var/log/athan-automation/athan.log
```

### Manual Testing

```bash
# Stop the service first so two instances don't run at once
sudo systemctl stop athan-automation.service

# Activate virtual environment
source /usr/local/share/athan-automation/venv/bin/activate

# Run the script
python /usr/local/bin/athan-automation
```

### Regenerate Prayer Times

When you need to update prayer times (e.g., new year, different location):

```bash
cd /usr/local/share/athan-automation/tools
./prayer_times_shell.sh
sudo systemctl restart athan-automation.service
```

## Finding Your Chromecast Device Names

To find the exact names of your Chromecast devices, run this with the virtual environment's Python (`/usr/local/share/athan-automation/venv/bin/python`):

```python
import pychromecast
chromecasts, browser = pychromecast.get_chromecasts()
for cc in chromecasts:
    print(cc.name)
browser.stop_discovery()
```

Or check the Google Home app on your phone.

## Web Server Configuration

### Lighttpd Configuration

Create `/etc/lighttpd/conf-available/99-athan.conf`:

```
alias.url += ( "/html/athan" => "/var/www/html/athan/" )
$HTTP["url"] =~ "^/html/athan/" {
    dir-listing.activate = "disable"
}
```

Enable and restart:
```bash
sudo ln -s /etc/lighttpd/conf-available/99-athan.conf /etc/lighttpd/conf-enabled/
sudo systemctl restart lighttpd
```

### Apache Configuration

Create `/etc/apache2/conf-available/athan.conf` (on Fedora/RHEL: `/etc/httpd/conf.d/athan.conf`):

```apache
Alias /html/athan/ /var/www/html/athan/
<Directory /var/www/html/athan/>
    Options -Indexes
    Require all granted
</Directory>
```

Enable and restart:
```bash
# Debian/Ubuntu
sudo a2enconf athan
sudo systemctl restart apache2

# Fedora/RHEL (no a2enconf needed)
sudo systemctl restart httpd
```

### Nginx Configuration

The setup script configures nginx automatically. To do it manually, add this to the `server` block in `/etc/nginx/sites-available/default` (on Fedora/RHEL: a file in `/etc/nginx/conf.d/`):

```nginx
location /html/athan {
    alias /var/www/html/athan/;
    autoindex off;
}
```

Restart:
```bash
sudo systemctl restart nginx
```

## Troubleshooting

### Chromecast Not Found

- Ensure your device is on the same network
- Check firewall settings (allow mDNS/port 5353)
- Verify the device name matches exactly (case-sensitive)
- Restart the Avahi daemon: `sudo systemctl restart avahi-daemon`
- If a VPN or other interface causes mDNS errors, set `zeroconf_interface` to this machine's LAN IP

### Audio Files Not Playing

- Verify web server is running: `sudo systemctl status nginx` (or `lighttpd` / `apache2` / `httpd`)
- Test audio URL in browser: `http://your-ip/html/athan/prayer/file.mp3`
- Check file permissions: `sudo chmod 644 /var/www/html/athan/*/*.mp3`
- Use your web server's IP address instead of its hostname in `lighttpd_base_url` (and the art URLs) in `/etc/athan-automation/config.ini`; Chromecasts often can't resolve local hostnames
- On Fedora/RHEL, restore SELinux labels: `sudo restorecon -Rv /var/www/html/athan/`

### Service Won't Start

- Check logs: `sudo journalctl -u athan-automation.service -n 50`
- Verify configuration: `sudo cat /etc/athan-automation/config.ini`
- Check prayer times file exists: `ls -l /var/lib/athan-automation/prayer_times.csv`

### Configuration Changes Not Taking Effect

The script re-reads `config.ini` automatically when it changes, but only picks up the new values when it next wakes up for a prayer. To apply changes immediately (for example, a new prayer times file), restart the service:
```bash
sudo systemctl restart athan-automation.service
```

### Prayer Times Calculator Issues

- Ensure dependencies are installed: `source /usr/local/share/athan-automation/venv/bin/activate && pip install praytimes hijridate`
- Check coordinates are valid (latitude: -90 to 90, longitude: -180 to 180)
- Verify date range is correct (end date after start date)

## Ramadan Mode

During Ramadan, the script automatically:
- Plays Iftar announcement 2.5 minutes before Maghrib (hard coded, you'll need to manually change that value if you use a different iftar audio file)
- Uses the `iftar_device` (can broadcast to speaker groups as well as individual speakers)
- Displays Iftar artwork
- Selects audio from the iftar folder

The built-in calculator fills in the Hijri month automatically. If you build the CSV yourself, set the "Month" column to "Ramadan" for those days.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Thanks to the pychromecast library developers
- Prayer times calculations based on various Islamic authorities
- All the beautiful Athan reciters

## Support

If you encounter any issues or have questions, please open an issue on GitHub.

---

**May Allah accept your prayers** 🤲
