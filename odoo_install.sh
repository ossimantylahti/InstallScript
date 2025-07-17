#!/bin/bash
################################################################################
# Script for installing Odoo on Ubuntu 16.04, 18.04, 20.04 and 22.04 (could be used for other version too)
# Author: Yenthe Van Ginneken
#-------------------------------------------------------------------------------
# This script will install Odoo on your Ubuntu server. It can install multiple Odoo instances
# in one Ubuntu with different xmlrpc_ports
#-------------------------------------------------------------------------------
# Make a new file:
#   sudo nano odoo-install.sh
# Place this content in it and then make the file executable:
#   sudo chmod +x odoo-install.sh
# Execute the script to install Odoo:
#   sudo ./odoo-install.sh
################################################################################

#--------------------------------------------------
# Begin configuration variables
#--------------------------------------------------

# Set the odoo server website name
WEBSITE_NAME="_"
# Set to true to install and configure nginx, "False" to skip nginx installation
INSTALL_NGINX="True"
# Set to "True" to install certbot and have ssl enabled, "False" to use http
ENABLE_SSL="True"
# Provide Email to register ssl certificate from Certbot
ADMIN_EMAIL="odoo@example.com"
# This will use the Let's Encrypt staging server to avoid hitting rate limits.
# Change to "False" when deploying to a live sever. Keep it "True" for testing purposes.
USE_LETSENCRYPT_STAGING="True"

# Choose the Odoo version which you want to install. For example: 16.0, 17.0, 18.0 or saas-22.
# This corresponds to the branch name in the Odoo GitHub repository.
OE_VERSION="16.0"

# Select to use Python virtual environment or not. For moden Ubuntus 22.0 and later, this is recommended.
# Note: for Python Pip installations the script is calling pip as pip3.
# For Virtual Environment installations, the script will use the pip from the virtual environment. $OE_VENV/bin/pip
USE_PYTHON_VENV="True"
# Wkhtmltopdf is required for printing PDF reports in Odoo.
INSTALL_WKHTMLTOPDF="True"
# Set the default Odoo port (you still have to use -c /etc/odoo-server.conf for example to use this.)
OE_PORT="8069"
# Set this to True if you want to install the Odoo enterprise version!
IS_ENTERPRISE="False"
# Installs postgreSQL V14 instead of defaults (e.g V12 for Ubuntu 20/22) - this improves performance
INSTALL_POSTGRESQL_FOURTEEN="True"
# Set the superadmin password - if GENERATE_RANDOM_PASSWORD is set to "True" we will automatically generate a random password, otherwise we use this one
OE_SUPERADMIN="admin"
# Set to "True" to generate a random password, "False" to use the variable in OE_SUPERADMIN
GENERATE_RANDOM_PASSWORD="True"
# Set the default Odoo longpolling port (you still have to use -c /etc/odoo-server.conf for example to use this.)
# Please note that the parameter in Odoo 11.0-15.00 is called longpolling_port. In Odoo 16.0 and later it is called gevent_port.
LONGPOLLING_PORT="8072"
#---------------------------------------------------
# Odoo default users and directories
OE_USER="odoo"
OE_CONFIG="${OE_USER}-server"
OE_HOME="/$OE_USER"
OE_HOME_EXT="/$OE_USER/${OE_USER}-server"
OE_VENV="$OE_HOME/venv"
# Number of workers to run. Set to 0 for no workers and werkzeug mode.
OE_WORKERS="2"
# Maximum number of cron jobs to run at the same time. Set to 0 for no cron jobs.
OE_MAX_CRON_THREADS="2"
#---------------------------------------------------

# ---------------------------------------------------
# END CONFIGURATION VARIABLES
# ---------------------------------------------------
# Set ANSI colors
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
RED='\033[1;31m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color
cd /tmp || { echo -e "${RED}FATAL ERROR${NC}. Failed to change directory to /tmp"; exit 1; }

# Enable logging
LOGFILE="odoo-install.log"
exec > >(awk '{ print strftime("[%Y-%m-%d %H:%M:%S]"), $0; fflush(); }' | tee -a "$LOGFILE") 2>&1

FULL_LOGFILE_PATH=$(readlink -f "$LOGFILE")
echo -e "${NC}Starting Odoo installation. "
echo -e "${GREEN}INFO:${NC} Logging enabled. Smart log to console and full log to ${BLUE}$LOGFILE${NC}."

echo -e "${GREEN}-----------------------------------------------------------${NC}"
#
##
###  WKHTMLTOPDF download links
## === Ubuntu Trusty x64 & x32 === (for other distributions please replace these two links,
## in order to have correct version of wkhtmltopdf installed, for a danger note refer to
## https://github.com/odoo/odoo/wiki/Wkhtmltopdf ):
## https://www.odoo.com/documentation/16.0/administration/install.html


# Check if the operating system is Ubuntu 22.04
if [[ $(lsb_release -r -s) == "22.04" || $(lsb_release -r -s) == "23.04" || $(lsb_release -r -s) == "23.10" || $(lsb_release -r -s) == "24.04" ]]; then
  # Use manually downloaded .deb from GitHub because system packages don't support Qt WebKit rendering
    WKHTMLTOX_X64="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6-1/wkhtmltox_0.12.6-1.stretch_amd64.deb"
    WKHTMLTOX_X32="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6-1/wkhtmltox_0.12.6-1.stretch_i386.deb"
else
    # For older versions of Ubuntu
    WKHTMLTOX_X64="https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.5/wkhtmltox_0.12.5-1.$(lsb_release -c -s)_amd64.deb"
    WKHTMLTOX_X32="https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.5/wkhtmltox_0.12.5-1.$(lsb_release -c -s)_i386.deb"
fi

#--------------------------------------------------
# Update Server
#--------------------------------------------------
echo -e "\n==== Updating Operating System and Repositories"
echo -e "\n---- Adding Ubuntu LTS specific repositories"
sudo add-apt-repository -y universe 1>/dev/null
echo -e "     ${GREEN}OK.${NC} Universe repository added."

if (( $(echo "$OE_VERSION < 13.0" | bc -l) )); then
  echo "    ${GREEN}INFO${NC}: Adding Xenial repo for legacy Odoo version $OE_VERSION"
  sudo add-apt-repository -y "deb http://mirrors.kernel.org/ubuntu/ xenial main" 1>/dev/null
  sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 40976EAF437D05B5 1>/dev/null
  sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 3B4FE6ACC0B21F32 1>/dev/null
  echo -e "    ${GREEN}OK.${NC} Legacy Odoo Linux repository support added.\n"
fi

sudo apt-get update -y 1>/dev/null
sudo apt-get upgrade -y 1>/dev/null
echo -e "     ${GREEN}OK.${NC} System packages updated."

# Development tools and compilers
echo -e "    \n---- Installing build tools and compilers"
sudo apt-get install -y gcc build-essential python3-dev python3-venv python3-wheel python3-setuptools 1>/dev/null
echo -e "     ${GREEN}OK.${NC} Build tools installed."

# PostgreSQL and authentication libraries
echo -e "    \n---- Installing PostgreSQL and authentication libraries"
sudo apt-get install -y libpq-dev libsasl2-dev libldap2-dev libssl-dev 1>/dev/null
echo -e "     ${GREEN}OK.${NC} PostgreSQL and authentication dependencies installed."

# Python & Odoo support packages
echo -e "    \n---- Installing core Python & Odoo dependency packages"
sudo apt-get install -y python3-cffi bc git wget plocate gdebi 1>/dev/null
echo -e "     ${GREEN}OK.${NC} Core Python/Odoo packages installed."

# Web rendering and compression libraries
echo -e "    \n---- Installing rendering and compression libraries"
sudo apt-get install -y libxslt-dev libzip-dev libpng-dev libjpeg-dev 1>/dev/null
echo -e "     ${GREEN}OK.${NC} Rendering and compression libraries installed."

# Frontend tools
echo -e "    \n---- Installing frontend tools (Node.js related)"
sudo apt-get install -y node-less 1>/dev/null
echo -e "     ${GREEN}OK.${NC} Frontend dependencies installed."
echo -e "     ${GREEN}OK.${NC} All operating system updates installed."

#--------------------------------------------------
# Install Dependencies
#--------------------------------------------------
echo "---- Ensuring server timezone data is up-to-date"
sudo apt-get install -y locales libc6 tzdata util-linux 1>/dev/null
sudo dpkg-reconfigure --frontend noninteractive tzdata
echo -e "     ${GREEN}OK.${NC} Server timezone data is updated."

#--------------------------------------------------
# Create user and directories
#--------------------------------------------------

echo -e "\n---- Creating Odoo system user"
sudo adduser --system --quiet --shell=/bin/bash --home=$OE_HOME --gecos 'ODOO' --group $OE_USER
#The user should also be added to the sudo'ers group.
sudo adduser $OE_USER sudo
# Just in case: fix home directory ownership 
sudo chown -R $OE_USER:$OE_USER $OE_HOME

echo -e "     ${GREEN}OK.${NC} Created system user ${BLUE}$OE_USER${NC} with home directory ${BLUE}/odoo${NC}."

echo -e "\n---- Create Log directory"
sudo mkdir /var/log/$OE_USER
sudo chown $OE_USER:$OE_USER /var/log/$OE_USER

echo -e "     ${GREEN}OK.${NC} Log directory created at ${BLUE}/var/log/$OE_USER${NC}."

#--------------------------------------------------
# Install PostgreSQL Server
#--------------------------------------------------

echo -e "\n---- Installing PostgreSQL Server"
if [ $INSTALL_POSTGRESQL_FOURTEEN = "True" ]; then
    echo -e "     ${YELLOW}NOTE${NC} Proceeding with postgreSQL V14 due to the user's choise"
    sudo curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc|sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
    sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
    sudo apt-get update 1>/dev/null
    sudo apt-get install -y postgresql-14 1>/dev/null
else
    echo -e "     ${YELLOW}NOTE${NC} Proceeding with the default postgreSQL version based on Linux version"
    sudo apt-get install -y postgresql postgresql-server-dev-all 1>/dev/null
fi
echo -e "     ${GREEN}OK.${NC} PostgreSQL server installed successfully."
POSTGRES_VERSION=$(psql --version | awk '{print $3}')
echo -e "     ${YELLOW}NOTE${NC} PostgreSQL version:${BLUE} $POSTGRES_VERSION${NC}"

echo -e "\n---- Creating Odoo PostgreSQL User "
sudo su - postgres -c "cd /tmp && createuser -s $OE_USER" 2> /dev/null || true
sudo -u postgres psql -c "DO \$\$ BEGIN
                            IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${OE_USER}') THEN
                                CREATE ROLE ${OE_USER} WITH LOGIN CREATEDB;
                            END IF;
                          END \$\$;"
                          
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname = 'odoo'" | grep -q 1 || \
sudo -u postgres createdb -O ${OE_USER} odoo


echo -e "     ${GREEN}OK.${NC} Odoo postgresql user created."
echo -e "     ${YELLOW}NOTE${NC} PostgreSQL user:${BLUE} $OE_USER${NC}"
sudo -u ${OE_USER} -H psql -d odoo -c '\q' || echo -e "     ${RED}WARNING${NC} Odoo user cannot access the database."

#--------------------------------------------------
# Install Python
#--------------------------------------------------

echo -e "\n--- Installing Python"

# Verify and install Python versions
install_python() {
  local v=$1
  if ! command -v python${v} &>/dev/null; then
    sudo add-apt-repository -y ppa:deadsnakes/ppa  1>/dev/null
    sudo apt-get update 1>/dev/null
    sudo apt-get install -y python${v} python${v}-venv python${v}-dev 1>/dev/null
  fi
}

case "$OE_VERSION" in
  "13.0")
    PYTHON_VER="3.6";;
  "14.0")
    PYTHON_VER="3.8";;
  "15.0"|"16.0")
    PYTHON_VER="3.9";;
  "17.0"|"18.0")
    PYTHON_VER="3.10";;
  "19.0")
    PYTHON_VER="3.11";; #Preliminary support for Odoo 19.0
  *)
    echo "Unsupported Odoo version: $OE_VERSION"; exit 1;;
esac

install_python "${PYTHON_VER}"

for pkg in gcc libpq-dev libsasl2-dev libldap2-dev libssl-dev; do
    dpkg -s $pkg &> /dev/null || { echo "Missing system packet: $pkg"; exit 1; }
done
echo -e "     ${GREEN}OK.${NC} Python ${BLUE}$PYTHON_VER${NC} installed successfully."

if [ "$USE_PYTHON_VENV" = "True" ]; then
  echo -e "\n---- Creating Python virtual environment at ${BLUE}${OE_VENV}${NC} "

  python${PYTHON_VER} -m venv ${OE_VENV}
  echo -e "     ${GREEN}OK.${NC} Python virtual environment created."

  echo -e "\n---- Checking Python version used in venv"
  VENV_PYTHON_VERSION=$($OE_VENV/bin/python3 --version)
  echo -e "     ${YELLOW}$VENV_PYTHON_VERSION${NC}"

  echo -e "\n---- Installing odoo pip requirements in virtual environment"
  ${OE_VENV}/bin/pip install --quiet --upgrade pip setuptools
  ${OE_VENV}/bin/pip install --quiet wheel
  ${OE_VENV}/bin/pip install --quiet -r https://github.com/odoo/odoo/raw/${OE_VERSION}/requirements.txt
  echo -e "     ${GREEN}OK.${NC} pip requirements installed in virtual environment."
  ${OE_VENV}/bin/pip install --quiet gevent greenlet zope.event
  echo -e "     ${GREEN}OK.${NC} pip gevent installed."
  ${OE_VENV}/bin/python3 -c "import zope.event; print('     OK. zope.event confirmed')"

else
  echo -e "\n---- Installing odoo pip requirements globally (no venv in use)"
  sudo -H pip3 install --quiet --break-system-packages -r https://github.com/odoo/odoo/raw/${OE_VERSION}/requirements.txt
  echo -e "     ${GREEN}OK.${NC} pip requirements installed globally."
  sudo pip3 install --quiet gevent greenlet zope.event
  echo -e "     ${GREEN}OK.${NC} pip gevent installed globally."
fi
if $OE_VENV/bin/python3 -m pip show gevent >/dev/null 2>&1; then
  echo -e "     ${GREEN}OK.${NC} gevent is installed and ready for workers mode."
else
  echo -e "     ${YELLOW}WARNING:${NC} gevent not found. Odoo uses werkzeug and does not support workers or longpolling."
fi

echo -e "\n---- Installing ${BLUE}NodeJS, NPM${NC} and ${BLUE}rtlcss${NC} for RTL stylesheet support"
sudo apt-get install -y nodejs npm 1>/dev/null
sudo npm install -g rtlcss 1>/dev/null
echo -e "     ${GREEN}OK.${NC} NodeJS, NPM and rtlcss installed."
echo -e "     ${YELLOW}NOTE${NC} Installed versions:"
echo -e "     ${BLUE}NodeJS${NC}   version: ${YELLOW}$(node -v)${NC}"
echo -e "     ${BLUE}NPM${NC}      version: ${YELLOW}$(npm -v)${NC}"
echo -e "     ${BLUE}rtlcss${NC}   version: ${YELLOW}$(rtlcss -v)${NC}"

#--------------------------------------------------
# Install Wkhtmltopdf (AppImage version)
#--------------------------------------------------
if [ "$INSTALL_WKHTMLTOPDF" = "True" ]; then
  echo -e "\n---- Installing ${BLUE}wkhtmltopdf${NC} via AppImage"
  # Define architecture-specific URL
  WKHTML_VER="0.12.6.1-3"
  OS_CODENAME=$(lsb_release -cs)  # jammy, focal, bullseye etc.
  ARCH=$(dpkg --print-architecture)  # amd64, arm64 etc.
  WKHTML_DEB="wkhtmltox_${WKHTML_VER}.${OS_CODENAME}_${ARCH}.deb"
  WKHTML_URL="https://github.com/wkhtmltopdf/packaging/releases/download/${WKHTML_VER}/${WKHTML_DEB}"

  curl -LO "$WKHTML_URL"
  if [ -f "$WKHTML_DEB" ]; then
    echo -e "     ${BLUE}INFO${NC}: Installing wkhtmltopdf dependencies...${NC}"
    sudo apt-get install -y xfonts-75dpi xfonts-base xfonts-encodings xfonts-utils 1>/dev/null
    echo -e "     ${GREEN}OK.${NC} wkhtmltopdf dependencies installed."
    sudo dpkg -i "$WKHTML_DEB" || sudo apt-get install -f -y
    echo -e "     ${GREEN}OK.${NC} wkhtmltopdf installed from ${BLUE}${WKHTML_DEB}.${NC}"

    # Clean up downloaded .deb file
    rm -f "$WKHTML_DEB"
  else
    echo -e "     ${RED}ERROR${NC}: Failed to download wkhtmltopdf from ${WKHTML_URL}${NC}"
  fi

  # Create symlink for wkhtmltoimage
  if ! command -v wkhtmltoimage >/dev/null 2>&1; then
    sudo ln -sf /usr/local/bin/wkhtmltopdf /usr/local/bin/wkhtmltoimage
    echo -e "     ${YELLOW}WARNING${NC}: wkhtmltoimage not found, created symlink to wkhtmltopdf.${NC}"
  fi

  if command -v wkhtmltopdf &> /dev/null; then
    echo -e "     ${GREEN}OK.${NC} wkhtmltopdf installed to ${BLUE}/usr/local/bin/wkhtmltopdf${NC}"
    echo -e "  wkhtmltopdf version: ${YELLOW}$(wkhtmltopdf -V | awk '{print $2}')${NC}"
  else
    echo -e "     ${YELLOW}WARNING${NC}: wkhtmltopdf installation may have failed. Binary not found."
  fi
else
  echo -e "     ${YELLOW}INFO${NC}: Skipped wkhtmltopdf as it was not selected for installation."
fi
  
sudo ln -s /usr/local/bin/wkhtmltopdf /usr/bin
sudo ln -s /usr/local/bin/wkhtmltoimage /usr/bin

echo -e "     ${GREEN}OK.${NC} wkhtmltopdf installed."
echo -e "     Installed version:"
echo -e "     ${BLUE}wkhtmltopdf${NC} version: ${YELLOW}$(wkhtmltopdf -V | awk '{print $2}')${NC}"
wkhtmltopdf -V
file /usr/local/bin/wkhtmltopdf

#--------------------------------------------------
# Install ODOO
#--------------------------------------------------
echo -e "\n==== Installing ODOO Server ===="
sudo git clone --quiet --depth 1 --branch $OE_VERSION https://www.github.com/odoo/odoo $OE_HOME_EXT/
echo -e "     ${GREEN}OK${NC}. Odoo ${BLUE}$OE_VERSION${NC} source cloned from GitHub to ${OE_HOME_EXT}${NC}."

if [ $IS_ENTERPRISE = "True" ]; then
    # Odoo Enterprise install!
    sudo pip3 install psycopg2-binary pdfminer.six 1>/dev/null
    echo -e "\n Creating symlink for node"
    sudo ln -s /usr/bin/nodejs /usr/bin/node
    sudo su $OE_USER -c "mkdir $OE_HOME/enterprise"
    sudo su $OE_USER -c "mkdir $OE_HOME/enterprise/addons"
    echo -e "     ${GREEN}OK.${NC} Symlinks created."

    GITHUB_RESPONSE=$(sudo git clone --depth 1 --branch $OE_VERSION https://www.github.com/odoo/enterprise "$OE_HOME/enterprise/addons" 2>&1)
    while [[ $GITHUB_RESPONSE == *"Authentication"* ]]; do
        echo "------------------------WARNING------------------------------"
        echo "Your authentication with Github has failed! Please try again."
        printf "In order to clone and install the Odoo enterprise version you \nneed to be an offical Odoo partner and you need access to\nhttp://github.com/odoo/enterprise.\n"
        echo "TIP: Press ctrl+c to stop this script."
        echo "-------------------------------------------------------------"
        echo " "
        GITHUB_RESPONSE=$(sudo git clone --depth 1 --branch $OE_VERSION https://www.github.com/odoo/enterprise "$OE_HOME/enterprise/addons" 2>&1)
    done

    echo -e "\n     ${GREEN}OK.${NC} Added Enterprise code under $OE_HOME/enterprise/addons"
    echo -e "\n---- Installing Enterprise specific libraries"
    sudo -H pip3 install num2words ofxparse dbfread ebaysdk firebase_admin pyOpenSSL
    sudo npm install -g less 1>/dev/null
    sudo npm install -g less-plugin-clean-css 1>/dev/null
    echo -e "     ${GREEN}OK.${NC} Enterprise specific libraries installed."
fi

echo -e "\n---- Creating custom module directory"
sudo su $OE_USER -c "mkdir $OE_HOME/custom"
sudo su $OE_USER -c "mkdir $OE_HOME/custom/addons"
echo -e "     ${GREEN}OK.${NC} Custom module directory created at ${BLUE}$OE_HOME/custom/addons${NC}."

echo -e "\n---- Setting permissions on home folder"
sudo chown -R $OE_USER:$OE_USER $OE_HOME/*
echo -e "     ${GREEN}OK.${NC} Home folder permissions set."


sudo touch /etc/${OE_CONFIG}.conf
echo -e "     ${GREEN}OK.${NC} Populating server configuration file"
sudo su root -c "printf '[options]\n' >> /etc/${OE_CONFIG}.conf"
sudo su root -c "printf 'db_user=${OE_USER}\n' >> /etc/${OE_CONFIG}.conf"
sudo su root -c "printf ';NOTE: This password allows database operations:\n' >> /etc/${OE_CONFIG}.conf"
if [ $GENERATE_RANDOM_PASSWORD = "True" ]; then
    OE_SUPERADMIN=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
    echo -e "     ${GREEN}OK.${NC}  Generated random admin password"
fi
# Verification that oe_superadmin is set (fallback)
if [ -z "$OE_SUPERADMIN" ]; then
    OE_SUPERADMIN="admin"
    echo -e "     ${YELLOW}NOTE.${NC} Admin password set to default 'admin' per user's choise."
fi

sudo su root -c "printf 'admin_passwd=${OE_SUPERADMIN}\n' >> /etc/${OE_CONFIG}.conf"

if [ "$(echo "$OE_VERSION > 11.0" | bc -l)" -eq 1 ]; then
  sudo su root -c "printf 'http_port=${OE_PORT}\n' >> /etc/${OE_CONFIG}.conf"
else
  sudo su root -c "printf 'xmlrpc_port=${OE_PORT}\n' >> /etc/${OE_CONFIG}.conf"
fi
sudo su root -c "printf 'logfile=/var/log/${OE_USER}/${OE_CONFIG}.log\n' >> /etc/${OE_CONFIG}.conf"

# Add longpolling or gevent port depending on Odoo version
# Odoo changed the longpolling_port to gevent_port in version 16.0
ODOO_MAJOR_VERSION=$(echo "$OE_VERSION" | cut -d '.' -f1)

if [ "$ODOO_MAJOR_VERSION" -ge 16 ]; then
  echo -e "     Adding gevent_port = $LONGPOLLING_PORT and workers to config (Odoo $OE_VERSION)"
  sudo su root -c "printf 'gevent_port=$LONGPOLLING_PORT\n' >> /etc/${OE_CONFIG}.conf"
  sudo su root -c "printf 'workers=$OE_WORKERS\n' >> /etc/${OE_CONFIG}.conf"
  sudo su root -c "printf 'max_cron_threads=$OE_MAX_CRON_THREADS\n' >> /etc/${OE_CONFIG}.conf"
else
  echo -e "     Adding longpolling_port=$LONGPOLLING_PORT to config (Odoo $OE_VERSION)"
  sudo su root -c "printf 'longpolling_port=$LONGPOLLING_PORT\n' >> /etc/${OE_CONFIG}.conf"
fi


if [ $IS_ENTERPRISE = "True" ]; then
    sudo su root -c "printf 'addons_path=${OE_HOME}/enterprise/addons,${OE_HOME_EXT}/addons\n' >> /etc/${OE_CONFIG}.conf"
else
    sudo su root -c "printf 'addons_path=${OE_HOME_EXT}/addons,${OE_HOME}/custom/addons\n' >> /etc/${OE_CONFIG}.conf"
fi

#Default limits configuration for Odoo server
#Soft memory limit is set to 512MB, hard limit to 1GB. This means that 
# 1. If Odoo cron job uses more than 512MB of memory, it will be killed before the next run
# 2. If Odoo cron job uses more than 1 gigagbyte of memory, it will be killed immediately
# 3. If one request (like http request) takes more than 60 seconds CPU time (not real time!), it will be killed
# 4. If one request (like report creation request) takes more than 120 real time, it will be killed

sudo su root -c "printf 'limit_memory_soft=512000000\n' >> /etc/${OE_CONFIG}.conf"
sudo su root -c "printf 'limit_memory_hard=1024000000\n' >> /etc/${OE_CONFIG}.conf"
sudo su root -c "printf 'limit_time_cpu=60\n' >> /etc/${OE_CONFIG}.conf"
sudo su root -c "printf 'limit_time_real=120\n' >> /etc/${OE_CONFIG}.conf"


sudo chown $OE_USER:$OE_USER /etc/${OE_CONFIG}.conf
sudo chmod 640 /etc/${OE_CONFIG}.conf

echo -e "     ${GREEN}OK.${NC} Configuration file created at ${BLUE}/etc/${OE_CONFIG}.conf${NC}."
#echo -e "\n---- Initializing database with base module"
#sudo -u ${OE_USER} ${OE_VENV}/bin/python3 ${OE_HOME}/odoo-bin -d ${OE_DB_NAME} -i base --config=/etc/${OE_CONFIG}.conf --without-demo=all --stop-after-init

#--------------------------------------------------
# Install Nginx if needed
#--------------------------------------------------
if [ $INSTALL_NGINX = "True" ]; then
  echo -e "\n---- Installing and setting up nginx"
  sudo apt-get install -y nginx 1>/dev/null
  cat <<EOF > ~/odoo
server {
  listen 80;

  # set proper server name after domain set
  server_name $WEBSITE_NAME;

  # Add Headers for odoo proxy mode
  proxy_set_header X-Forwarded-Host \$host;
  proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto \$scheme;
  proxy_set_header X-Real-IP \$remote_addr;
  add_header X-Frame-Options "SAMEORIGIN";
  add_header X-XSS-Protection "1; mode=block";
  proxy_set_header X-Client-IP \$remote_addr;
  proxy_set_header HTTP_X_FORWARDED_HOST \$remote_addr;

  #   odoo    log files
  access_log  /var/log/nginx/$OE_USER-access.log;
  error_log       /var/log/nginx/$OE_USER-error.log;

  #   increase    proxy   buffer  size
  proxy_buffers   16  64k;
  proxy_buffer_size   128k;

  proxy_read_timeout 900s;
  proxy_connect_timeout 900s;
  proxy_send_timeout 900s;

  #   force   timeouts    if  the backend dies
  proxy_next_upstream error   timeout invalid_header  http_500    http_502
  http_503;

  types {
    text/less less;
    text/scss scss;
  }

  #   enable  data    compression
  gzip    on;
  gzip_min_length 1100;
  gzip_buffers    4   32k;
  gzip_types  text/css text/less text/plain text/xml application/xml application/json application/javascript application/pdf image/jpeg image/png;
  gzip_vary   on;
  client_header_buffer_size 4k;
  large_client_header_buffers 4 64k;
  client_max_body_size 0;

  location / {
    proxy_pass    http://127.0.0.1:$OE_PORT;
    # by default, do not forward anything
    proxy_redirect off;
  }

  location /longpolling {
    proxy_pass http://127.0.0.1:$LONGPOLLING_PORT;
  }

  location ~* .(js|css|png|jpg|jpeg|gif|ico)$ {
    expires 2d;
    proxy_pass http://127.0.0.1:$OE_PORT;
    add_header Cache-Control "public, no-transform";
  }

  # cache some static data in memory for 60mins.
  location ~ /[a-zA-Z0-9_-]*/static/ {
    proxy_cache_valid 200 302 60m;
    proxy_cache_valid 404      1m;
    proxy_buffering    on;
    expires 864000;
    proxy_pass    http://127.0.0.1:$OE_PORT;
  }
}
EOF

  sudo mv ~/odoo /etc/nginx/sites-available/$WEBSITE_NAME
  
  # Symbolic link the configuration file to sites-enabled does not support _, thus protected.
  if [ ! -e "/etc/nginx/sites-enabled/$WEBSITE_NAME" ]; then
    sudo ln -s /etc/nginx/sites-available/$WEBSITE_NAME /etc/nginx/sites-enabled/$WEBSITE_NAME
  fi
  [ -e /etc/nginx/sites-enabled/default ] && sudo rm /etc/nginx/sites-enabled/default

  sudo service nginx reload
  sudo su root -c "printf 'proxy_mode=True\n' >> /etc/${OE_CONFIG}.conf"
  echo -e "     ${GREEN}OK${NC}. The Nginx server is up and running. Configuration can be found at ${BLUE}/etc/nginx/sites-available/$WEBSITE_NAME${NC}."
else
  echo "     ${YELLOW}INFO${NC}. Nginx is not installed due to user's choise."
fi

#--------------------------------------------------
# Enable ssl with certbot
#--------------------------------------------------

if [ $INSTALL_NGINX = "True" ] && [ $ENABLE_SSL = "True" ] && [ $ADMIN_EMAIL != "odoo@example.com" ]  && [ $WEBSITE_NAME != "_" ];then
  echo -e "\n---- Installing ${BLUE}Certbot${NC} and enabling SSL/HTTPS"
  sudo apt-get update -y 1>/dev/null
  sudo apt-get install -y python3-certbot-nginx 1>/dev/null
  sudo apt-get install -y snapd 1>/dev/null
  echo -e "     ${GREEN}OK.${NC} snapd installed.${NC}."
  sudo snap version 1>/dev/null || { echo -e "     ${RED}ERROR${NC}: Snap is not installed or not working. Please install snapd and try again."; exit 1; }
  sudo snap install core 1>/dev/null
  sudo snap refresh core 1>/dev/null
  echo -e "     ${GREEN}OK.${NC} snap core refreshed.${NC}."
    #--------------------------------------------------
    # Validate snapd.socket status before using Certbot
    #--------------------------------------------------
    echo -e "${YELLOW}-- Checking snapd.socket service status...${NC}"
    SNAPD_STATUS=$(sudo systemctl is-active snapd.socket)

    if [[ "$SNAPD_STATUS" == "active" ]]; then
        echo -e "${GREEN}     OK${NC}. snapd.socket is active and listening.${NC}"
    else
        echo -e "${RED}     ERROR${NC}. snapd.socket is not active (status: $SNAPD_STATUS). Certbot installation may fail.${NC}"
        echo -e "${RED}     You can try starting it manually: sudo systemctl start snapd.socket${NC}"
    fi
    #--------------------------------------------------
    # Installing Certbot using snap and validating
    #--------------------------------------------------
    echo -e "${YELLOW}-- Installing Certbot via snap...${NC}"
    if sudo snap install --classic certbot 1>/dev/null; then
        echo -e "${GREEN}     OK${NC}. Certbot installed successfully via snap.${NC}"
    else
        echo -e "${RED}     ERROR${NC}. Failed to install Certbot via snap.${NC}"
        echo -e "${NC}     Please verify snapd is functioning and try again manually:${NC}"
        echo -e "${NC}     sudo snap install --classic certbot${NC}"
    fi

  if [ "$USE_LETSENCRYPT_STAGING" = "True" ]; then
    CERTBOT_STAGE_ARG="--staging"
    echo -e "     ${YELLOW}NOTE:${NC} Using Let's Encrypt ${YELLOW}staging test${NC} environment to avoid rate limits."
    echo -e "     ${YELLOW}NOTE:${NC} This is for testing and development servers only." 
    echo -e "     ${YELLOW}NOTE:${NC} Use ${BLUE}USE_LETSENCRYPT_STAGING=False${NC} for production environment deployment."
  else
    echo -e "     ${YELLOW}NOTE:${NC} Using Let's Encrypt ${YELLOW}production${NC} environment."
    CERTBOT_STAGE_ARG=""
  fi
  sudo certbot --nginx $CERTBOT_STAGE_ARG -d "$WEBSITE_NAME" --non-interactive --agree-tos -m "$ADMIN_EMAIL" --redirect --keep-until-expiring

  sudo service nginx reload
  echo -e "     ${GREEN}OK.${NC} Certbot is installed and SSL/HTTPS enabled for ${BLUE}$WEBSITE_NAME${NC}."
  if [ "$USE_LETSENCRYPT_STAGING" = "True" ]; then
    echo -e "     ${YELLOW}NOTE${NC}: Certbot is using the Let's Encrypt staging and thus web browser can show a certificate warning."
  fi
else
  echo "${GREEN}INFO${NC}: SSL/HTTPS is not enabled due to user's choise or because of a misconfiguration!"
  if [ $ADMIN_EMAIL = "odoo@example.com" ]; then 
    echo -e "     ${RED}ERROR${NC} Certbot does not support registering with ${YELLOW}odoo@example.com${NC}. Please use a real e-mail address."
  fi
  if [ $WEBSITE_NAME = "_" ]; then
    echo -e "     ${RED}ERROR${NC} Website name is set as ${YELLOW}_${NC}. Cannot obtain SSL Certificate for _. Please use a real website address."
  fi
fi

echo -e "     ${BLUE}INFO.${NC} Creating systemd service file for Odoo"

cat <<EOF | sudo tee /etc/systemd/system/$OE_CONFIG.service > /dev/null
[Unit]
Description=Odoo daemon
Requires=postgresql.service
After=network.target postgresql.service

[Service]
Type=simple
User=$OE_USER
Group=$OE_USER
ExecStart=${OE_VENV}/bin/python3 ${OE_HOME}/odoo-bin --config=/etc/${OE_CONFIG}.conf
StandardOutput=journal
StandardError=journal
Restart=on-failure
SyslogIdentifier=odoo

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable $OE_CONFIG
sudo systemctl start $OE_CONFIG

echo -e "     ${BLUE}INFO.${NC} Starting Odoo Service"

echo -e "     ${BLUE}INFO.${NC} Waiting for Odoo to start and listen listening on port $OE_PORT"

# Wait for Odoo to start and listen on the specified port
for i in {1..5}; do
    if sudo lsof -i :$OE_PORT | grep LISTEN >/dev/null; then
        echo -e "     ${GREEN}OK.${NC} Odoo is now running and listening on port " $OE_PORT
        break
    fi
    sleep 1
done

if ! sudo lsof -i :$OE_PORT | grep LISTEN >/dev/null; then
    echo -e "     ${RED}ERROR:${NC} Odoo is not listening on port $OE_PORT after waiting up to 5 seconds."
    echo "     please check logs at /var/log/${OE_USER}/${OE_CONFIG}.log"
fi

echo -e "\n---- Testing HTTP on longpolling port ${LONGPOLLING_PORT}"

if curl -s --max-time 2 http://localhost:${LONGPOLLING_PORT} > /dev/null; then
    echo -e "     ${GREEN}OK.${NC} Longpolling or gevent port ${LONGPOLLING_PORT} is responding."
else
    echo -e "     ${RED}ERROR.${NC} Longpolling gevent port ${LONGPOLLING_PORT} is not respond."
    sudo ss -ltnp | grep ":${LONGPOLLING_PORT}" 
fi


if pgrep -f odoo-bin >/dev/null; then
    echo -e "     ${GREEN}OK.${NC} Odoo process is running."
else
    echo -e "     ${YELLOW}Warning${NC}: Odoo process not found even though port is open."
fi

if [ -f /var/log/${OE_USER}/${OE_CONFIG}.log ]; then
  echo -e "\n     Latest Odoo log output tail:"
  echo -e "     /var/log/${OE_USER}/${OE_CONFIG}.log"
  sudo tail -n 20 /var/log/${OE_USER}/${OE_CONFIG}.log
else
  echo -e "     ${RED}ERROR${NC}: No log file found at /var/log/${OE_USER}/${OE_CONFIG}.log"
fi

# Get server IP address (first non-loopback IPv4)
SERVER_IP=$(hostname -I | awk '{print $1}')

echo -e "${GREEN}Enabling Odoo to start on system boot...${NC}"

sudo systemctl enable odoo-server > /dev/null 2>&1 && \
echo -e "${GREEN}OK${NC}. Odoo service enabled successfully.${NC}" || \
echo -e "${RED}ERROR${NC}. Failed to enable Odoo service. You can try manually: sudo systemctl enable odoo-server${NC}"

#--------------------------------------------------
# Final Odoo service validation with error flagging
#--------------------------------------------------

echo -e "\n${YELLOW}Validating Odoo service configuration and status...${NC}"

validation_failed=false

# 1. Check that the Odoo config file exists
echo -e "${YELLOW}-- Reading Odoo configuration file: /etc/${OE_CONFIG}.conf${NC}"
if sudo test -f /etc/${OE_CONFIG}.conf; then
    sudo cat /etc/${OE_CONFIG}.conf
else
    echo -e "${RED}Missing configuration file: /etc/${OE_CONFIG}.conf${NC}"
    validation_failed=true
fi

# 2. Check if Odoo service is running
echo -e "\n${YELLOW}-- Checking systemd service status for odoo-server.${NC}"
if sudo systemctl is-active --quiet odoo-server; then
    echo -e "${GREEN}Odoo service is running.${NC}"
else
    echo -e "${RED}Odoo service is NOT running.${NC}"
    validation_failed=true
fi

# 3. Show the latest Odoo logs
echo -e "\n${YELLOW}-- Showing last 50 lines of Odoo log (/var/log/odoo/odoo-server.log)...${NC}"
if sudo test -f /var/log/odoo/odoo-server.log; then
    sudo tail -n 50 /var/log/odoo/odoo-server.log
else
    echo -e "${RED}Log file not found: /var/log/odoo/odoo-server.log${NC}"
    validation_failed=true
fi

# 4. Show journal entries
echo -e "\n${YELLOW}-- Fetching recent journal entries (last 50 lines)...${NC}"
if sudo journalctl -u odoo-server -n 50 --no-pager >/dev/null 2>&1; then
    sudo journalctl -u odoo-server -n 50 --no-pager
else
    echo -e "${RED}No journal entries found for odoo-server.${NC}"
    validation_failed=true
fi

# 5. Check if Odoo is listening on HTTP port
echo -e "\n${YELLOW}-- Verifying if Odoo is listening on port ${OE_PORT} (HTTP)...${NC}"
if sudo lsof -i :${OE_PORT} | grep LISTEN >/dev/null; then
    echo -e "${GREEN}Odoo is listening on port ${OE_PORT}.${NC}"
else
    echo -e "${RED}Nothing is listening on port ${OE_PORT}.${NC}"
    validation_failed=true
fi

# 6. Check if Odoo is listening on longpolling port
echo -e "\n${YELLOW}-- Verifying if Odoo is listening on port ${LONGPOLLING_PORT} (Longpolling)...${NC}"
if sudo lsof -i :${LONGPOLLING_PORT} | grep LISTEN >/dev/null; then
    echo -e "${GREEN}Odoo is listening on port ${LONGPOLLING_PORT}.${NC}"
else
    echo -e "${RED}Nothing is listening on port ${LONGPOLLING_PORT}.${NC}"
    validation_failed=true
fi

# Summary
if $validation_failed; then
    echo -e "\n${RED}Validation failed.${NC} Please fix the above errors before proceeding.${NC}"
    exit 1
else
    echo -e "\n${GREEN}Validation successfull.${NC} All checks passed.${NC}"
fi



echo -e "${GREEN}-----------------------------------------------------------"
echo -e "Script done. Odoo is now installed and running. Configuration summary:"
echo -e "-----------------------------------------------------------${NC}\n"

echo -e "${YELLOW} Odoo version:           ${NC}$ODOO_VERSION"
echo -e "${YELLOW} Service user:           ${NC}$OE_USER"
echo -e "${YELLOW} HTTP port:              ${NC}$OE_PORT"
echo -e "${YELLOW} Longpolling port:       ${NC}$LONGPOLLING_PORT"
echo -e "${YELLOW} Configuration file:     ${NC}/etc/${OE_CONFIG}.conf"
echo -e "${YELLOW} Log file:               ${NC}/var/log/$OE_USER/odoo-server.log"
echo -e "${YELLOW} Addons folder:          ${NC}/odoo/custom/addons/"
echo -e "${YELLOW} Superadmin password:    ${NC}$OE_SUPERADMIN"
echo -e "${YELLOW} Codebase location:      ${NC}/odoo/odoo-server"
echo -e "${YELLOW} Python virtualenv:      ${NC}/odoo/venv"
echo -e "${YELLOW} Full installation log:  ${NC}$FULL_LOGFILE_PATH"
echo -e ""
echo -e "\n${GREEN} Systemd service '${OE_CONFIG}' created and started.${NC}"
echo -e " Start:     sudo systemctl start $OE_CONFIG"
echo -e " Stop:      sudo systemctl stop $OE_CONFIG"
echo -e " Restart:   sudo systemctl restart $OE_CONFIG"
echo -e " Status:    sudo systemctl status $OE_CONFIG"
echo -e " Logs:      journalctl -u $OE_CONFIG -f"

if [ "$INSTALL_NGINX" = "True" ]; then
  echo -e "\n${GREEN} Nginx is installed and configured.${NC}"
  echo -e " Site config: /etc/nginx/sites-available/$WEBSITE_NAME"
  echo -e " Public URL:  http://$WEBSITE_NAME/"
fi

echo -e "\n${GREEN} Access Odoo in your browser and create your database:${NC}"
echo -e " http://$SERVER_IP:$OE_PORT/web/database/manager"

echo -e "${GREEN}-----------------------------------------------------------${NC}\n"