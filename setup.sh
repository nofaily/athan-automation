#!/bin/bash

# Athan Automation Setup Script
# This script helps set up the athan automation system following Linux FHS conventions
# REVISED: Implements robust VENV creation and the correct Nginx configuration.

set -e

echo "================================"
echo "Athan Automation Setup (Automated)"
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

# Check if running with sufficient privileges for system directories
if [ "$EUID" -eq 0 ]; then 
    echo -e "${RED}Error: Running as root. This script should be run as a regular user.${NC}"
    echo "The script will prompt for sudo when needed."
    exit 1
fi

echo ""
echo -e "${BLUE}This setup is fully automated.${NC}"
echo "Installation will proceed automatically."
echo ""

read -p "Continue with installation? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
fi

# --- Helper Functions ---

# Function to install Nginx
install_webserver() {
    echo -e "${YELLOW}No web server detected. Installing Nginx...${NC}"
    sudo apt-get install -y nginx
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Nginx installed successfully.${NC}"
        WEB_SERVER="nginx"
    else
        echo -e "${RED}Error: Failed to install Nginx. Please install a web server manually.${NC}"
        WEB_SERVER=""
    fi
}

# Function to configure a detected or installed web server
configure_webserver() {
    local WEB_SERVER_CONFIGURED=1
    case $1 in
        lighttpd)
            echo "Configuring lighttpd..."
            sudo tee /etc/lighttpd/conf-available/99-athan.conf > /dev/null <<EOF
alias.url += ( "/html/athan" => "/var/www/html/athan" )
\$HTTP["url"] =~ "^/html/athan/" {
    dir-listing.activate = "disable"
}
EOF
            sudo ln -sf /etc/lighttpd/conf-available/99-athan.conf /etc/lighttpd/conf-enabled/
            sudo systemctl reload lighttpd || echo -e "${YELLOW}Warning: Failed to reload lighttpd. Please check manually.${NC}"
            echo -e "${GREEN}✓ Configured lighttpd${NC}"
            WEB_SERVER_CONFIGURED=0
            ;;
        apache2)
            echo "Configuring apache2..."
            sudo tee /etc/apache2/conf-available/athan.conf > /dev/null <<EOF
Alias /html/athan /var/www/html/athan
<Directory /var/www/html/athan>
    Options -Indexes
    Require all granted
</Directory>
EOF
            sudo a2enconf athan || echo -e "${YELLOW}Warning: Failed to enable apache2 configuration.${NC}"
            sudo systemctl reload apache2 || echo -e "${YELLOW}Warning: Failed to reload apache2. Please check manually.${NC}"
            echo -e "${GREEN}✓ Configured apache2${NC}"
            WEB_SERVER_CONFIGURED=0
            ;;
        nginx)
            echo "Configuring nginx (Dedicated Site File)..."
            
            # Define file paths
            NGINX_SITE_AVAILABLE="/etc/nginx/sites-available/athan-automation.conf"
            NGINX_SITE_ENABLED="/etc/nginx/sites-enabled/athan-automation.conf"
            
            # The Athan Automation server block configuration
            # This creates a dedicated site config using the correct FHS structure.
            sudo tee "$NGINX_SITE_AVAILABLE" > /dev/null <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name _;
    root /var/www/html;
    index index.html;

    # Athan Automation - Dedicated alias for serving audio files
    location /html/athan {
        alias /var/www/html/athan/;
        autoindex off;
    }
    
    location / {
        try_files \$uri \$uri/ =404;
    }

}
EOF

            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✓ Created dedicated Nginx configuration file: $NGINX_SITE_AVAILABLE${NC}"
            else
                echo -e "${RED}Error: Failed to create Nginx configuration file.${NC}"
                WEB_SERVER_CONFIGURED=1
                return
            fi
            
            # Disable the default site to ensure our new site handles port 80 correctly
            if [ -f /etc/nginx/sites-enabled/default ]; then
                echo -e "${YELLOW}Disabling default Nginx site to prevent port conflict...${NC}"
                sudo rm /etc/nginx/sites-enabled/default
            fi

            # Create the symlink to enable the new site
            if [ ! -L "$NGINX_SITE_ENABLED" ]; then
                sudo ln -s "$NGINX_SITE_AVAILABLE" "$NGINX_SITE_ENABLED"
                echo -e "${GREEN}✓ Enabled athan-automation site.${NC}"
            fi

            echo "Testing Nginx configuration..."
            if sudo nginx -t; then # Outputs test results directly
                echo -e "${GREEN}✓ Nginx configuration test successful.${NC}"
                sudo systemctl reload nginx
                echo -e "${GREEN}✓ Reloaded nginx service.${NC}"
                WEB_SERVER_CONFIGURED=0
            else
                echo -e "${RED}Error: Nginx configuration failed test. Check $NGINX_SITE_AVAILABLE manually.${NC}"
                WEB_SERVER_CONFIGURED=1
            fi
            ;;
    esac
    return $WEB_SERVER_CONFIGURED
}

# --- Installation Steps ---

# 1. Initial System Dependency Installation
echo ""
echo "Installing core system dependencies (requires sudo)..."
sudo apt-get update
sudo apt-get install -y python3-pip python3-venv avahi-daemon
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: Python 3 failed to install. Cannot continue.${NC}"
    exit 1
fi
PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
echo -e "${GREEN}✓ Found Python $PYTHON_VERSION${NC}"
echo -e "${GREEN}✓ Core dependencies installed.${NC}"
echo ""

# 2. Create directory structure
echo "Creating directory structure..."
echo "Creating system directories (requires sudo)..."
sudo mkdir -p /etc/athan-automation
sudo mkdir -p /var/lib/athan-automation
sudo mkdir -p /var/www/html/athan/{fajr,prayer,iftar}
sudo mkdir -p /var/log/athan-automation
sudo mkdir -p /usr/local/share/athan-automation/tools

# Set ownership to current user
sudo chown -R $USER:$USER /var/www/html/athan
sudo chown -R $USER:$USER /var/log/athan-automation
sudo chown -R $USER:$USER /var/lib/athan-automation

echo -e "${GREEN}✓ Created system directories${NC}"

# 3. Create virtual environment (ROBUST CHECK)
echo ""
echo "Creating Python virtual environment..."
VENV_PATH="$HOME/athan-automation-env"
ACTIVATE_SCRIPT="$VENV_PATH/bin/activate" # The essential file to check

# Check if the virtual environment exists AND is complete
if [ -d "$VENV_PATH" ] && [ -f "$ACTIVATE_SCRIPT" ]; then
    echo -e "${YELLOW}⚠ Virtual environment already exists and is complete at $VENV_PATH${NC}"
else
    # If the directory exists but is incomplete, or doesn't exist, we must create it
    if [ -d "$VENV_PATH" ]; then
        echo -e "${YELLOW}⚠ Found incomplete virtual environment. Removing and recreating...${NC}"
        rm -rf "$VENV_PATH"
    fi

    # Attempt creation
    python3 -m venv "$VENV_PATH"
    
    # Check if creation succeeded and the essential 'activate' script exists
    if [ $? -eq 0 ] && [ -f "$ACTIVATE_SCRIPT" ]; then
        echo -e "${GREEN}✓ Created virtual environment at $VENV_PATH${NC}"
    else
        echo -e "${RED}Error: Failed to create Python virtual environment or the 'activate' script is missing.${NC}"
        echo -e "${RED}Check Python installation and disk space/permissions.${NC}"
        exit 1
    fi
fi

# 4. Install Python dependencies
echo ""
echo "Installing Python dependencies..."
source "$ACTIVATE_SCRIPT"
pip install --upgrade pip > /dev/null 2>&1
# Assuming requirements.txt is in the current directory
if [ -f requirements.txt ]; then
    pip install -r requirements.txt
    echo -e "${GREEN}✓ Installed dependencies${NC}"
else
    echo -e "${YELLOW}⚠ requirements.txt not found. Skipping dependency install.${NC}"
fi
deactivate

# 5. Install configuration file
echo ""
echo "Setting up configuration..."
CONFIG_FILE="/etc/athan-automation/config.ini"
if [ ! -f "$CONFIG_FILE" ]; then
    if [ -f config/config.ini.sample ]; then
        sudo cp config/config.ini.sample "$CONFIG_FILE"
        sudo chown $USER:$USER "$CONFIG_FILE"
        sudo chmod 644 "$CONFIG_FILE"
        echo -e "${GREEN}✓ Created configuration file${NC}"
        echo -e "${YELLOW}⚠ Please edit /etc/athan-automation/config.ini with your settings${NC}"
    else
        echo -e "${RED}Error: config/config.ini.sample not found${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠ Configuration file already exists, skipping${NC}"
fi

# 6. Install main script and tools
echo ""
echo "Installing main script and prayer times calculator..."
TOOLS_DIR="/usr/local/share/athan-automation/tools"

if [ -f athan_automation.py ]; then
    sudo cp athan_automation.py /usr/local/bin/athan-automation
    sudo chmod 755 /usr/local/bin/athan-automation
    echo -e "${GREEN}✓ Installed athan-automation to /usr/local/bin/${NC}"
fi

if [ -f tools/prayer_times_python.py ] && [ -f tools/prayer_times_shell.sh ]; then
    sudo cp tools/prayer_times_python.py "$TOOLS_DIR/"
    sudo cp tools/prayer_times_shell.sh "$TOOLS_DIR/"
    sudo chmod 755 "$TOOLS_DIR/prayer_times_shell.sh"
    sudo chmod 644 "$TOOLS_DIR/prayer_times_python.py"
    echo -e "${GREEN}✓ Installed prayer times calculator tools${NC}"
else
    echo -e "${YELLOW}⚠ Prayer times tools not found, skipping tool installation.${NC}"
fi

# 7. Web server installation and configuration
echo ""
echo "Checking and configuring web server..."
WEB_SERVER=""
if systemctl is-active --quiet lighttpd; then
    WEB_SERVER="lighttpd"
elif systemctl is-active --quiet apache2; then
    WEB_SERVER="apache2"
elif systemctl is-active --quiet nginx; then
    WEB_SERVER="nginx"
fi

if [ -z "$WEB_SERVER" ]; then
    install_webserver # Installs Nginx if no other is found
fi

if [ ! -z "$WEB_SERVER" ]; then
    echo -e "${GREEN}✓ Web server detected/installed: $WEB_SERVER${NC}"
    configure_webserver "$WEB_SERVER"
    # CRITICAL FIX: Explicitly echo a newline after the complex execution block
    # to ensure the shell parser correctly moves to the next command.
    echo "" 
fi

# 8. Check for avahi (mDNS) - Already installed in step 1
echo "Checking Avahi daemon status..."
if systemctl is-active --quiet avahi-daemon; then
    echo -e "${GREEN}✓ avahi-daemon is running${NC}"
else
    echo -e "${YELLOW}⚠ avahi-daemon is not running. Starting it...${NC}"
    sudo systemctl start avahi-daemon || echo -e "${RED}Error: Failed to start avahi-daemon.${NC}"
fi

# 9. System service setup (AUTOMATED)
echo ""
echo "Setting up systemd service automatically..."

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

# 10. Generate initial prayer times file
echo ""
echo "Generating initial prayer times file..."
PRAYER_TIMES_SCRIPT="/usr/local/share/athan-automation/tools/prayer_times_shell.sh"

if [ -f "$PRAYER_TIMES_SCRIPT" ]; then
    echo -e "${YELLOW}Running $PRAYER_TIMES_SCRIPT... (You will be prompted for location settings)${NC}"
    
    # Run the script from its installed directory
    (
        cd /usr/local/share/athan-automation/tools
        # The script handles its own venv activation and file movement
        ./prayer_times_shell.sh
    )
    
    # Check if the file was created by the sub-script
    if [ -f /var/lib/athan-automation/prayer_times.csv ]; then
        echo -e "${GREEN}✓ Initial prayer times generated and installed.${NC}"
    else
        echo -e "${RED}Error: Prayer times CSV was not found after running the generator.${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Prayer times script not found, skipping generation.${NC}"
fi


# Summary
echo ""
echo "================================"
echo "Setup Complete!"
echo "================================"
echo ""
echo -e "${GREEN}Installation Summary:${NC}"
echo "  ✓ Configuration: /etc/athan-automation/config.ini"
echo "  ✓ Main script: /usr/local/bin/athan-automation"
echo "  ✓ Web Server: $WEB_SERVER (configured for Athan files)"
echo "  ✓ Prayer Times: Generated and installed at /var/lib/athan-automation/prayer_times.csv"
echo "  ✓ System Service: Installed, but NOT YET ENABLED/STARTED."
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Add your Athan MP3 files and Artwork images to /var/www/html/athan/"
echo ""
echo "2. Edit configuration to update IP address, device names, and volume levels:"
echo "   nano /etc/athan-automation/config.ini"
echo ""
echo "3. Enable and start the service:"
echo "   sudo systemctl enable athan-automation.service"
echo "   sudo systemctl start athan-automation.service"
echo ""
echo "To check the service status:"
echo "   sudo systemctl status athan-automation.service"
