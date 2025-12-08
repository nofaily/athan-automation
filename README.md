# Athan Automation for Chromecast

Automatically play the Islamic call to prayer (Athan) on your Chromecast devices at the correct prayer times. This Python script reads prayer times from a CSV file and broadcasts beautiful Athan recitations to your Google Cast-enabled speakers or displays.

## Features

- Automatic Athan playback at all five daily prayer times
- Random selection from multiple Athan audio files
- Special Ramadan support with Iftar announcements (announcement is hard-coded to start earlier than prayer time to allow of anticipatory tune)
- Supports multiple Chromecast devices
- Configurable volume levels (separate settings for Fajr and other prayers)
- Displays beautiful Islamic artwork during playback
- ID3 metadata support (shows reciter name, title, etc.)
- Hot-reload configuration without restarting
- Comprehensive logging with rotation
- Automatic retry and error recovery
- Built-in prayer times calculator

## Prerequisites

- Raspberry Pi or Linux server (can run 24/7)
- Python 3.7 or higher
- Google Chromecast devices on the same network
- Web server (lighttpd, Apache, or nginx) to serve audio files

## Installation

### 1. Clone the Repository

```bash
git clone https://github.com/nofaily/athan-automation.git
cd athan-automation
```

### 2. Install System Dependencies

```bash
sudo apt-get update
sudo apt-get install -y python3-pip python3-venv avahi-daemon
```

### 3. Run the Setup Script

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

### 4. Add Your Audio Files

Place your Athan MP3 files in the appropriate directories:
- `/var/www/html/files/athan/fajr/` - Fajr Athan files
- `/var/www/html/files/athan/prayer/` - Regular prayer Athan files
- `/var/www/html/files/athan/iftar/` - Ramadan Iftar announcement files

**Note:** Make sure your MP3 files have proper ID3 tags (title, artist, album) for best display on Chromecast devices.

### 5. Add Artwork (Optional)

Place artwork images in `/var/www/html/files/athan/`:
- `Mohamed_Ali_Mosque.jpg` - Displayed during regular prayers
- `Iftar.jpg` - Displayed during Ramadan Iftar

### 6. Configure Your Settings

Edit the configuration file:

```bash
nano /etc/athan-automation/config.ini
```

Update the following settings:
- `lighttpd_base_url` - Your server's IP address (doesn't have to be lighttpd, any webserver would work fine)
- `athan_device` - Name of your Chromecast device
- `iftar_device` - Device for Ramadan announcements
- Volume levels as preferred

### 7. Generate Prayer Times

The project includes a prayer times calculator. Run it to generate your prayer schedule:

```bash
source ~/athan-automation-env/bin/activate
cd /usr/local/share/athan-automation/tools
./prayer_times_shell.sh
```

Follow the prompts to:
- Enter your location coordinates (latitude/longitude) (you can get those from Google Maps)
- Select calculation method (MWL, ISNA, Karachi, etc.) (if you're unsure, see the default prayer calculation settings on your Athan app)
- Choose Asr method (Shafi'i or Hanafi) (if you're unsure, see your Athan app)
- Specify date range

The script will generate `prayer_times.csv` in the current directory. Move it to the data directory:

```bash
sudo mv prayer_times.csv /var/lib/athan-automation/prayer_times.csv
```

**Alternative:** You can also generate prayer times from:
- [IslamicFinder.org](https://www.islamicfinder.org/)
- [Adhan API](https://aladhan.com/prayer-times-api)

### 8. Enable and Start the Service

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
└── athan-automation            # Main script (symlink)

/var/lib/athan-automation/      # Application data
└── prayer_times.csv            # Prayer times schedule

/var/www/html/files/            # Web server files
└── athan/                      # Audio files and artwork
    ├── fajr/                   # Fajr audio files
    ├── prayer/                 # Regular prayer audio files
    ├── iftar/                  # Iftar audio files
    ├── Mohamed_Ali_Mosque.jpg  # Prayer artwork
    └── Iftar.jpg               # Iftar artwork

/var/log/athan-automation/      # Log files
└── athan.log                   # Application logs

~/athan-automation-env/         # Python virtual environment

/usr/local/share/athan-automation/  # Shared resources
└── tools/                      # Prayer times calculator
    ├── prayer_times_python.py
    └── prayer_times_shell.sh
```

## Configuration

### Main Configuration File

The `/etc/athan-automation/config.ini` file contains all settings:

```ini
[DEFAULT]
fajr_folder = /var/www/html/files/athan/fajr
prayer_folder = /var/www/html/files/athan/prayer
iftar_folder = /var/www/html/files/athan/iftar
prayer_times_file = /var/lib/athan-automation/prayer_times.csv
lighttpd_base_url = http://raspberry.pi/athan
athan_art_url = http://raspberry.pi/athan/Mohamed_Ali_Mosque.jpg
iftar_art_url = http://raspberry.pi/athan/Iftar.jpg
athan_device = Kitchen Display
iftar_device = All speakers
log_file = /var/log/athan-automation/athan.log
athan_volume_level = 0.4
fajr_volume_level = 0.2
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
# Activate virtual environment
source ~/athan-automation-env/bin/activate

# Run the script
python /usr/local/bin/athan-automation
```

### Regenerate Prayer Times

When you need to update prayer times (e.g., new year, different location):

```bash
source ~/athan-automation-env/bin/activate
cd /usr/local/share/athan-automation/tools
./prayer_times_shell.sh
sudo mv prayer_times.csv /var/lib/athan-automation/prayer_times.csv
sudo systemctl restart athan-automation.service
```

## Finding Your Chromecast Device Names

To find the exact names of your Chromecast devices:

```python
import pychromecast
chromecasts, browser = pychromecast.get_chromecasts()
for cc in chromecasts:
    print(cc.name)
```

Or check the Google Home app on your phone.

## Web Server Configuration

### Lighttpd Configuration

Create `/etc/lighttpd/conf-available/99-athan.conf`:

```
alias.url += ( "/athan" => "/var/www/html/files/athan/" )
$HTTP["url"] =~ "^/athan/" {
    dir-listing.activate = "disable"
}
```

Enable and restart:
```bash
sudo ln -s /etc/lighttpd/conf-available/99-athan.conf /etc/lighttpd/conf-enabled/
sudo systemctl restart lighttpd
```

### Apache Configuration

Create `/etc/apache2/conf-available/athan.conf`:

```apache
Alias /athan /var/www/html/files/athan/
<Directory /var/www/html/files/athan/>
    Options -Indexes
    Require all granted
</Directory>
```

Enable and restart:
```bash
sudo a2enconf athan
sudo systemctl restart apache2
```

### Nginx Configuration

Add to `/etc/nginx/sites-available/default`:

```nginx
location /athan {
    alias /var/www/html/files/athan/;
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

### Audio Files Not Playing

- Verify web server is running: `sudo systemctl status lighttpd`
- Test audio URL in browser: `http://your-ip/athan/prayer/file.mp3`
- Check file permissions: `sudo chmod 644 /var/local/athan/audio/**/*.mp3`

### Service Won't Start

- Check logs: `sudo journalctl -u athan-automation.service -n 50`
- Verify configuration: `sudo cat /etc/athan-automation/config.ini`
- Check prayer times file exists: `ls -l /var/lib/athan-automation/prayer_times.csv`

### Configuration Changes Not Taking Effect

The script hot-reloads configuration automatically, but you can restart:
```bash
sudo systemctl restart athan-automation.service
```

### Prayer Times Calculator Issues

- Ensure dependencies are installed: `source ~/athan-automation-env/bin/activate && pip install praytimes hijridate`
- Check coordinates are valid (latitude: -90 to 90, longitude: -180 to 180)
- Verify date range is correct (end date after start date)

## Ramadan Mode

During Ramadan, the script automatically:
- Plays Iftar announcement 2.5 minutes before Maghrib (hard coded, you'll need to manually change that value if you use a different iftar file)
- Uses the `iftar_device` (can broadcast to speaker groups as well as individual speakers)
- Displays Iftar artwork
- Selects audio from the iftar folder

Simply set the "Month" column to "Ramadan" in your prayer times CSV.

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
