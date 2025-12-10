#!/bin/bash

# Athan Automation Setup Script
# This script helps set up the athan automation system following Linux FHS conventions

set -e

echo "================================"
echo "Athan Automation Setup"
echo "================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if running on Linux
if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    echo -e "${RED}Error: This script is designed for Linux systems.${NC}"
    exit 1
fi

# Check if Python 3 is installed
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: Python 3 is not installed.${NC}"
    echo "Please install Python 3.7 or higher:"
    echo "  sudo apt-get install python3 python3-pip python3-venv"
    exit 1
fi

PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
echo -e "${GREEN}✓ Found Python $PYTHON_VERSION${NC}"

# Check if running with sufficient privileges for system directories
if [ "$EUID" -eq 0 ]; then 
    echo -e "${YELLOW}⚠ Running as root. This is not recommended.${NC}"
    echo "Please run as a regular user. The script will prompt for sudo when needed."
    exit 1
fi

echo ""
echo -e "${BLUE}This setup follows Linux Filesystem Hierarchy Standard (FHS):${NC}"
echo "  • /etc/athan-automation/          - Configuration"
echo "  • /var/lib/athan-automation/      - Application data"
echo "  • /var/www/html/athan/            - Audio files"
echo "  • /var/log/athan-automation/      - Log files"
echo "  • /usr/local/bin/                 - Executables"
echo "  • /usr/local/share/athan-automation/ - Tools and resources"
echo ""

read -p "Continue with installation? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
fi

# ========================================
# 1. Create directory structure
# ========================================
echo ""
echo "Creating directory structure..."

# System directories (requires sudo)
echo "Creating system directories (requires sudo)..."
sudo mkdir -p /etc/athan-automation
sudo mkdir -p /var/lib/athan-automation
sudo mkdir -p /var/www/html/athan/{fajr,prayer,iftar}
sudo mkdir -p /var/log/athan-automation
sudo mkdir -p /usr/local/share/athan-automation/tools

# Set ownership to current user
sudo chown -R $USER:$USER /var/www/html/athan
sudo chown $USER:$USER /var/log/athan-automation
sudo chown $USER:$USER /var/lib/athan-automation

echo -e "${GREEN}✓ Created system directories${NC}"

# ========================================
# 2. Create virtual environment
# ========================================
echo ""
echo "Creating Python virtual environment..."
VENV_PATH="$HOME/athan-automation-env"
if [ ! -d "$VENV_PATH" ]; then
    python3 -m venv "$VENV_PATH"
    echo -e "${GREEN}✓ Created virtual environment at $VENV_PATH${NC}"
else
    echo -e "${YELLOW}⚠ Virtual environment already exists at $VENV_PATH${NC}"
fi

# ========================================
# 3. Install Python dependencies
# ========================================
echo ""
echo "Installing Python dependencies..."
source "$VENV_PATH/bin/activate"
pip install --upgrade pip > /dev/null 2>&1
pip install -r requirements.txt
echo -e "${GREEN}✓ Installed dependencies${NC}"

# ========================================
# 4. Install configuration file
# ========================================
echo ""
echo "Setting up configuration..."
if [ ! -f /etc/athan-automation/config.ini ]; then
    if [ -f config/config.ini.sample ]; then
        sudo cp config/config.ini.sample /etc/athan-automation/config.ini
        sudo chown $USER:$USER /etc/athan-automation/config.ini
        sudo chmod 644 /etc/athan-automation/config.ini
        echo -e "${GREEN}✓ Created configuration file${NC}"
        echo -e "${YELLOW}⚠ Please edit /etc/athan-automation/config.ini with your settings${NC}"
    else
        echo -e "${RED}Error: config/config.ini.sample not found${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠ Configuration file already exists, skipping${NC}"
fi

# ========================================
# 5. Install main script
# ========================================
echo ""
echo "Installing main script..."
if [ -f athan_automation.py ]; then
    sudo cp athan_automation.py /usr/local/bin/athan-automation
    sudo chmod 755 /usr/local/bin/athan-automation
    echo -e "${GREEN}✓ Installed athan-automation to /usr/local/bin/${NC}"
else
    echo -e "${RED}Error: athan_automation.py not found${NC}"
    exit 1
fi

# ========================================
# 6. Install prayer times tools
# ========================================
echo ""
echo "Installing prayer times calculator..."
if [ -f tools/prayer_times_python.py ] && [ -f tools/prayer_times_shell.sh ]; then
    sudo cp tools/prayer_times_python.py /usr/local/share/athan-automation/tools/
    sudo cp tools/prayer_times_shell.sh /usr/local/share/athan-automation/tools/
    sudo chmod 755 /usr/local/share/athan-automation/tools/prayer_times_shell.sh
    sudo chmod 644 /usr/local/share/athan-automation/tools/prayer_times_python.py
    echo -e "${GREEN}✓ Installed prayer times calculator${NC}"
else
    echo -e "${YELLOW}⚠ Prayer times tools not found, skipping${NC}"
fi

# ========================================
# 7. Create sample prayer times
# ========================================
echo ""
if [ ! -f /var/lib/athan-automation/prayer_times.csv ]; then
    if [ -f examples/prayer_times_sample.csv ]; then
        cp examples/prayer_times_sample.csv /var/lib/athan-automation/prayer_times.csv
        chmod 644 /var/lib/athan-automation/prayer_times.csv
        echo -e "${GREEN}✓ Created sample prayer times file${NC}"
        echo -e "${YELLOW}⚠ Please generate your own prayer times or update the file${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Prayer times file already exists, skipping${NC}"
fi

# ========================================
# 8. Web server configuration
# ========================================
echo ""
echo "Checking for web server..."
WEB_SERVER=""
if systemctl is-active --quiet lighttpd; then
    WEB_SERVER="lighttpd"
    echo -e "${GREEN}✓ lighttpd is running${NC}"
elif systemctl is-active --quiet apache2; then
    WEB_SERVER="apache2"
    echo -e "${GREEN}✓ apache2 is running${NC}"
elif systemctl is-active --quiet nginx; then
    WEB_SERVER="nginx"
    echo -e "${GREEN}✓ nginx is running${NC}"
else
    echo -e "${YELLOW}⚠ No web server detected.${NC}"
    echo "You need a web server to serve audio files."
    echo "Install lighttpd with: sudo apt-get install lighttpd"
fi

if [ ! -z "$WEB_SERVER" ]; then
    echo ""
    echo "Would you like to configure $WEB_SERVER to serve Athan files? (y/n)"
    read -r response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        case $WEB_SERVER in
            lighttpd)
                sudo tee /etc/lighttpd/conf-available/99-athan.conf > /dev/null <<EOF
alias.url += ( "/html/athan" => "/var/www/html/athan" )
\$HTTP["url"] =~ "^/html/athan/" {
    dir-listing.activate = "disable"
}
EOF
                sudo ln -sf /etc/lighttpd/conf-available/99-athan.conf /etc/lighttpd/conf-enabled/
                sudo systemctl reload lighttpd
                echo -e "${GREEN}✓ Configured lighttpd${NC}"
                ;;
            apache2)
                sudo tee /etc/apache2/conf-available/athan.conf > /dev/null <<EOF
Alias /html/athan /var/www/html/athan
<Directory /var/www/html/athan>
    Options -Indexes
    Require all granted
</Directory>
EOF
                sudo a2enconf athan
                sudo systemctl reload apache2
                echo -e "${GREEN}✓ Configured apache2${NC}"
                ;;
            nginx)
                echo -e "${YELLOW}Please manually add the following to your nginx configuration:${NC}"
                echo ""
                echo "location /athan {"
                echo "    alias /var/www/html/files/athan;"
                echo "    autoindex off;"
                echo "}"
                ;;
        esac
    fi
fi

# ========================================
# 9. Check for avahi (mDNS)
# ========================================
echo ""
echo "Checking for Avahi daemon (required for Chromecast discovery)..."
if systemctl is-active --quiet avahi-daemon; then
    echo -e "${GREEN}✓ avahi-daemon is running${NC}"
else
    echo -e "${YELLOW}⚠ avahi-daemon is not running${NC}"
    echo "Install and start with:"
    echo "  sudo apt-get install avahi-daemon"
    echo "  sudo systemctl start avahi-daemon"
fi

# ========================================
# 10. System service setup
# ========================================
echo ""
echo "Would you like to set up the systemd service? (y/n)"
read -r response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo "Setting up systemd service..."
    
    # Create a customized service file
    SERVICE_FILE="/tmp/athan-automation.service"
    cat > $SERVICE_FILE << EOF
[Unit]
Description=Athan Automation Service
After=network.target time-sync.target
Wants=time-sync.target

[Service]
User=$USER
WorkingDirectory=/var/lib/athan-automation
ExecStart=$HOME/athan-automation-env/bin/python /usr/local/bin/athan-automation
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    sudo cp $SERVICE_FILE /etc/systemd/system/athan-automation.service
    sudo systemctl daemon-reload
    
    echo -e "${GREEN}✓ Installed systemd service${NC}"
    echo ""
    echo "To enable and start the service:"
    echo "  sudo systemctl enable athan-automation.service"
    echo "  sudo systemctl start athan-automation.service"
else
    echo "Skipping systemd service setup"
fi

# ========================================
# Summary
# ========================================
echo ""
echo "================================"
echo "Setup Complete!"
echo "================================"
echo ""
echo -e "${GREEN}Installation Summary:${NC}"
echo "  ✓ Configuration: /etc/athan-automation/config.ini"
echo "  ✓ Main script: /usr/local/bin/athan-automation"
echo "  ✓ Data directory: /var/lib/athan-automation/"
echo "  ✓ Audio directory: /var/www/html/athan"
echo "  ✓ Log directory: /var/log/athan-automation/"
echo "  ✓ Prayer times tools: /usr/local/share/athan-automation/tools/"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Add your Athan MP3 files: Fajr, regular prayer and iftar files"
echo "   cp your-files/*.mp3 /var/www/html/athan/fajr/"
echo "   cp your-files/*.mp3 /var/www/html/athan/prayer/"
echo "   cp your-files/*.mp3 /var/www/html/athan/iftar/"
echo ""
echo "2. Add artwork images (optional):"
echo "   cp mosque.jpg /var/www/html/athan/Mohamed_Ali_Mosque.jpg"
echo "   cp iftar.jpg /var/www/html/athan/Iftar.jpg"
echo ""
echo "3. Edit configuration:"
echo "   nano /etc/athan-automation/config.ini"
echo "   (Update IP address, device names, and volume levels)"
echo ""
echo "4. Generate prayer times:"
echo "   source ~/athan-automation-env/bin/activate"
echo "   cd /usr/local/share/athan-automation/tools"
echo "   ./prayer_times_shell.sh"
echo "   mv prayer_times.csv /var/lib/athan-automation/"
echo ""
echo "5. Enable and start the service:"
echo "   sudo systemctl enable athan-automation.service"
echo "   sudo systemctl start athan-automation.service"
echo ""
echo "6. Check status and logs:"
echo "   sudo systemctl status athan-automation.service"
echo "   sudo tail -f /var/log/athan-automation/athan.log"
echo ""
echo ""
echo "For more information, see README.md"
echo "Report issues at: https://github.com/nofaily/athan-automation/issues"
