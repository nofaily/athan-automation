#!/bin/bash

# Athan Automation Setup Script (Adaptive)
# This script automatically detects the Linux distribution (Debian/Ubuntu or Fedora/RHEL)
# and adjusts installation commands and configurations accordingly.

set -e

echo "================================"
echo "Athan Automation Setup (Adaptive)"
echo "================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Distribution Detection & Variable Setup ---

# Check if running on Linux
if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    echo -e "${RED}Error: This script is designed for Linux systems.${NC}"
    exit 1
fi

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID=$ID
else
    echo -e "${RED}Error: Cannot determine Linux distribution (/etc/os-release not found). Aborting.${NC}"
    exit 1
fi

echo -e "${BLUE}Detected OS: $OS_ID${NC}"

# Define key variables based on the detected OS
case "$OS_ID" in
    debian|ubuntu)
        PKG_MANAGER="apt-get"
        UPDATE_CMD="update"
        CORE_PKGS="python3-pip python3-venv avahi-daemon"
        WEB_SERVER_PKGS="nginx"
        APACHE_SERVICE="apache2"
        NGINX_CONF_AVAILABLE="/etc/nginx/sites-available/athan-automation.conf"
        NGINX_CONF_ENABLED="/etc/nginx/sites-enabled/athan-automation.conf"
        NGINX_DEFAULT_CONF="/etc/nginx/sites-enabled/default"
        AVAHI_SERVICE="avahi-daemon"
        ;;
    fedora|centos|rhel)
        PKG_MANAGER="dnf"
        UPDATE_CMD="check-update" # Use check-update for faster initial DNF check
        CORE_PKGS="python3-pip avahi avahi-tools"
        WEB_SERVER_PKGS="nginx"
        APACHE_SERVICE="httpd"
        NGINX_CONF_AVAILABLE="/etc/nginx/conf.d/athan-automation.conf"
        NGINX_CONF_ENABLED="/etc/nginx/conf.d/athan-automation.conf" # Same file for DNF systems
        NGINX_DEFAULT_CONF="" # Not typically used/needed for DNF-based Nginx setup
        AVAHI_SERVICE="avahi-daemon.service"
        ;;
    *)
        echo -e "${RED}Error: Unsupported distribution: $OS_ID. Only Debian/Ubuntu and Fedora/RHEL derivatives are supported.${NC}"
        exit 1
        ;;
esac

echo -e "${GREEN}Using package manager: $PKG_MANAGER${NC}"
echo ""

# Check if running with sufficient privileges
if [ "$EUID" -eq 0 ]; then 
    echo -e "${RED}Error: Running as root. This script should be run as a regular user.${NC}"
    echo "The script will prompt for sudo when needed."
    exit 1
fi

read -p "Continue with installation? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
fi

# --- Helper Functions (Use defined variables) ---

# Function to install Nginx
install_webserver() {
    echo -e "${YELLOW}No web server detected. Installing Nginx using $PKG_MANAGER...${NC}"
    sudo $PKG_MANAGER install -y $WEB_SERVER_PKGS
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
    local SERVER_NAME=$1
    echo "Configuring $SERVER_NAME..."

    case $SERVER_NAME in
nginx)
            # Nginx Configuration (Adaptive Path)
            
            # --- Check and Disable Default Config (Fedora/RHEL Specific) ---
            if [ "$OS_ID" == "fedora" ] || [ "$OS_ID" == "centos" ] || [ "$OS_ID" == "rhel" ]; then
                DEFAULT_CONF_FEDORA="/etc/nginx/conf.d/welcome.conf"
                if [ -f "$DEFAULT_CONF_FEDORA" ]; then
                    echo -e "${YELLOW}Disabling default Nginx welcome page: $DEFAULT_CONF_FEDORA...${NC}"
                    # Rename the file to .disabled to prevent Nginx from loading it
                    sudo mv "$DEFAULT_CONF_FEDORA" "$DEFAULT_CONF_FEDORA.disabled"
                fi
            fi

            # --- Create Athan Automation Config (Path is Adaptive) ---
            
            # The Athan Automation server block configuration
            sudo tee "$NGINX_CONF_AVAILABLE" > /dev/null <<EOF
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
                echo -e "${GREEN}✓ Created Nginx configuration file: $NGINX_CONF_AVAILABLE${NC}"
            else
                echo -e "${RED}Error: Failed to create Nginx configuration file.${NC}"
                return 1
            fi
            
            # --- Adaptive logic for enabling the site (Debian/Ubuntu only) ---
            if [ "$NGINX_CONF_AVAILABLE" != "$NGINX_CONF_ENABLED" ]; then
                # Debian/Ubuntu: sites-available/sites-enabled logic
                
                # Disable the default site
                if [ -f "$NGINX_DEFAULT_CONF" ]; then
                    echo -e "${YELLOW}Disabling default Nginx site to prevent port conflict...${NC}"
                    sudo rm "$NGINX_DEFAULT_CONF"
                fi
                
                # Create the symlink to enable the new site
                if [ ! -L "$NGINX_CONF_ENABLED" ]; then
                    sudo ln -s "$NGINX_CONF_AVAILABLE" "$NGINX_CONF_ENABLED"
                    echo -e "${GREEN}✓ Enabled athan-automation site via symlink.${NC}"
                fi
            fi

            # --- Test and Start/Reload Service ---
            echo "Testing Nginx configuration..."
            if sudo nginx -t; then
                echo -e "${GREEN}✓ Nginx configuration test successful.${NC}"

                if systemctl is-active --quiet nginx; then
                    sudo systemctl reload nginx
                    echo -e "${GREEN}✓ Reloaded nginx service.${NC}"
                else
                    sudo systemctl start nginx
                    echo -e "${GREEN}✓ Started nginx service.${NC}"
                fi

                WEB_SERVER_CONFIGURED=0
            else
                echo -e "${RED}Error: Nginx configuration failed test. Check $NGINX_CONF_AVAILABLE manually.${NC}"
                WEB_SERVER_CONFIGURED=1
            fi
            ;;
            
        lighttpd|apache2|httpd)
            echo -e "${YELLOW}Warning: Full adaptive configuration for $SERVER_NAME is complex and skipped.${NC}"
            echo -e "${YELLOW}Please configure the '/html/athan' alias manually to point to '/var/www/html/athan'.${NC}"
            WEB_SERVER_CONFIGURED=1
            ;;
        *)
            echo -e "${RED}Error: Cannot configure unknown web server $SERVER_NAME.${NC}"
            WEB_SERVER_CONFIGURED=1
            ;;
    esac
    return $WEB_SERVER_CONFIGURED
}

# --- Installation Steps ---

# 1. Initial System Dependency Installation
echo ""
echo "Installing core system dependencies (requires sudo)..."
sudo $PKG_MANAGER $UPDATE_CMD
sudo $PKG_MANAGER install -y $CORE_PKGS

if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: Python 3 failed to install. Cannot continue.${NC}"
    exit 1
fi
PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
echo -e "${GREEN}✓ Found Python $PYTHON_VERSION${NC}"
echo -e "${GREEN}✓ Core dependencies installed.${NC}"
echo ""

# 2. Create directory structure (Paths are FHS standard and non-adaptive)
echo "Creating directory structure..."
sudo mkdir -p /etc/athan-automation
sudo mkdir -p /var/lib/athan-automation
sudo mkdir -p /var/www/html/athan/{fajr,prayer,iftar}
sudo mkdir -p /var/log/athan-automation
sudo mkdir -p /usr/local/share/athan-automation
sudo mkdir -p /usr/local/share/athan-automation/tools

# Set ownership to current user
sudo chown -R $USER:$USER /var/www/html/athan
sudo chown -R $USER:$USER /var/log/athan-automation
sudo chown -R $USER:$USER /var/lib/athan-automation
sudo chown -R $USER:$USER /usr/local/share/athan-automation

echo -e "${GREEN}✓ Created system directories${NC}"

# 3. Create virtual environment
echo ""
echo "Creating Python virtual environment..."
VENV_PATH="/usr/local/share/athan-automation/venv"
ACTIVATE_SCRIPT="$VENV_PATH/bin/activate"

if [ -d "$VENV_PATH" ] && [ -f "$ACTIVATE_SCRIPT" ]; then
    echo -e "${YELLOW}⚠ Virtual environment already exists and is complete at $VENV_PATH${NC}"
else
    if [ -d "$VENV_PATH" ]; then
        echo -e "${YELLOW}⚠ Found incomplete virtual environment. Removing and recreating...${NC}"
        rm -rf "$VENV_PATH"
    fi

    python3 -m venv "$VENV_PATH"
    
    if [ $? -eq 0 ] && [ -f "$ACTIVATE_SCRIPT" ]; then
        echo -e "${GREEN}✓ Created virtual environment at $VENV_PATH${NC}"
    else
        echo -e "${RED}Error: Failed to create Python virtual environment.${NC}"
        exit 1
    fi
fi

# 4. Install Python dependencies
echo ""
echo "Installing Python dependencies..."
source "$ACTIVATE_SCRIPT"
pip install --upgrade pip > /dev/null 2>&1

if [ -f requirements.txt ]; then
    pip install -r requirements.txt
    echo -e "${GREEN}✓ Installed dependencies${NC}"
else
    echo -e "${YELLOW}⚠ requirements.txt not found. Skipping dependency install.${NC}"
fi
deactivate

# 5. Install configuration file (Non-adaptive)
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

# 6. Install main script and tools (Non-adaptive)
echo ""
echo "Installing main script and prayer times calculator..."
TOOLS_DIR="/usr/local/share/athan-automation/tools"

if [ -f athan_automation.py ]; then
    sudo cp athan_automation.py /usr/local/bin/athan-automation
    sudo chmod 755 /usr/local/bin/athan-automation
    echo -e "${GREEN}✓ Installed athan-automation to /usr/local/bin/${NC}"
fi

if [ -f tools/prayer_times_python.py ] && [ -f tools/prayer_times_shell.sh ]; then
    # Use the newly adaptive shell script
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
# Check for common web servers (use the correct service names if possible)
if systemctl is-active --quiet lighttpd; then
    WEB_SERVER="lighttpd"
elif systemctl is-active --quiet $APACHE_SERVICE; then
    WEB_SERVER="$APACHE_SERVICE"
elif systemctl is-active --quiet nginx; then
    WEB_SERVER="nginx"
fi

if [ -z "$WEB_SERVER" ]; then
    install_webserver # Installs Nginx if no other is found
fi

if [ ! -z "$WEB_SERVER" ]; then
    echo -e "${GREEN}✓ Web server detected/installed: $WEB_SERVER${NC}"
    configure_webserver "$WEB_SERVER"
    echo "" 
fi

# 8. Check for avahi (mDNS) - Uses adaptive service name
echo "Checking Avahi daemon status..."
if systemctl is-active --quiet $AVAHI_SERVICE; then
    echo -e "${GREEN}✓ $AVAHI_SERVICE is running${NC}"
else
    echo -e "${YELLOW}⚠ $AVAHI_SERVICE is not running. Starting it...${NC}"
    sudo systemctl start $AVAHI_SERVICE || echo -e "${RED}Error: Failed to start $AVAHI_SERVICE.${NC}"
fi

# 9. System service setup (Non-adaptive service path)
echo ""
echo "Setting up systemd service automatically..."

# Create a customized service file (Uses $USER variable)
SERVICE_FILE="/tmp/athan-automation.service"
cat > $SERVICE_FILE << EOF
[Unit]
Description=Athan Automation Service
After=network.target time-sync.target
Wants=time-sync.target

[Service]
User=$USER
WorkingDirectory=/var/lib/athan-automation
ExecStart=/usr/local/share/athan-automation/venv/bin/python /usr/local/bin/athan-automation
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
    
    (
        cd /usr/local/share/athan-automation/tools
        ./prayer_times_shell.sh # This is now the adaptive script
    )
    
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
echo -e "${GREEN}Installation Summary (Adaptive):${NC}"
echo "  ✓ Configuration: /etc/athan-automation/config.ini"
echo "  ✓ Main script: /usr/local/bin/athan-automation"
echo "  ✓ Web Server: $WEB_SERVER (configured for Athan files)"
echo "  ✓ Package Manager: $PKG_MANAGER"
echo "  ✓ Avahi Service: $AVAHI_SERVICE"
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
