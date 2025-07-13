#!/bin/bash
################################################################################
# Script for installing Odoo on Ubuntu 16.04, 18.04, 20.04 and 22.04 (could be used for other version too)
# AuthorS: Yenthe Van Ginneken and Ossi Mantylahti
#-------------------------------------------------------------------------------
# This script will install Odoo on your Ubuntu server. It can install multiple Odoo instances
# in one Ubuntu because of the different xmlrpc_ports
#-------------------------------------------------------------------------------
# Make a new file:
# sudo nano odoo-install.sh
# Place this content in it and then make the file executable:
# sudo chmod +x odoo-install.sh
# Execute the script to install Odoo:
# ./odoo-install
################################################################################
LOGFILE="odoo-install.log"
exec > >(tee -a "$LOGFILE") 2> >(tee -a "$LOGFILE" >&2)
exec > >(awk '{ print strftime("[%Y-%m-%d %H:%M:%S]"), $0; fflush(); }' >> "$LOGFILE") 2>&1
FULL_LOGFILE_PATH=$(readlink -f "$LOGFILE")

#--------------------------------------------------
# Variables
#--------------------------------------------------

OE_USER="odoo"
OE_HOME="/$OE_USER"
OE_HOME_EXT="/$OE_USER/${OE_USER}-server"
# The default port where this Odoo instance will run under (provided you use the command -c in the terminal)
# Set to true if you want to install it, false if you don't need it or have it already installed.

# Ubuntu environments have made system installed python3 packages very difficutl to manage. Henceforth, we will use a virtual environment for Odoo.
# This will ensure that Odoo has its own Python environment and does not conflict with system packages
# This is the default location where the Odoo virtual environment will be created.
#
# Note: for Python Pip installations the script is calling pip as pip3. 
# For Virtual Environment installations, it will use the pip from the virtual environment. $OE_VENV/bin/pip
USE_PYTHON_VENV="True"
# If USE_PYTHON_VENV is True, this is the location of the virtual environment.
OE_VENV="$OE_HOME/venv"

INSTALL_WKHTMLTOPDF="True"
# Set the default Odoo port (you still have to use -c /etc/odoo-server.conf for example to use this.)
OE_PORT="8069"
# Choose the Odoo version which you want to install. For example: 16.0, 15.0, 14.0 or saas-22. When using 'master' the master version will be installed.
# IMPORTANT! This script contains extra libraries that are specifically needed for Odoo 16.0
OE_VERSION="16.0"
# Set this to True if you want to install the Odoo enterprise version!
IS_ENTERPRISE="False"
# Installs postgreSQL V14 instead of defaults (e.g V12 for Ubuntu 20/22) - this improves performance
INSTALL_POSTGRESQL_FOURTEEN="True"
# Set this to True if you want to install Nginx!
INSTALL_NGINX="False"
# Set the superadmin password - if GENERATE_RANDOM_PASSWORD is set to "True" we will automatically generate a random password, otherwise we use this one
OE_SUPERADMIN="admin"
# Set to "True" to generate a random password, "False" to use the variable in OE_SUPERADMIN
GENERATE_RANDOM_PASSWORD="True"
OE_CONFIG="${OE_USER}-server"
# Set the website name
WEBSITE_NAME="_"
# Set the default Odoo longpolling port (you still have to use -c /etc/odoo-server.conf for example to use this.)
LONGPOLLING_PORT="8072"
# Set to "True" to install certbot and have ssl enabled, "False" to use http
ENABLE_SSL="True"
# Provide Email to register ssl certificate
ADMIN_EMAIL="odoo@example.com"
#
# ---------------------------------------------------
# END CONFIGURATION VARIABLES
# ---------------------------------------------------
#
##
###  WKHTMLTOPDF download links
## === Ubuntu Trusty x64 & x32 === (for other distributions please replace these two links,
## in order to have correct version of wkhtmltopdf installed, for a danger note refer to
## https://github.com/odoo/odoo/wiki/Wkhtmltopdf ):
## https://www.odoo.com/documentation/16.0/administration/install.html

# ANSI colors
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
RED='\033[1;31m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

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
echo -e "\n---- Updating Operating system ----"
# universe package is for Ubuntu 18.x
sudo add-apt-repository -y universe 1>/dev/null
# libpng12-0 dependency for wkhtmltopdf for older Ubuntu versions is only available in Xenial.
# Xenial repositories are end-of-life and should not be used in production.
# Warning: adding Xenial repositories can cause conflicts with newer packages and result to errors in apt-get.
if (( $(echo "$OE_VERSION < 13.0" | bc -l) )); then
  echo "Adding Xenial repo for legacy Odoo version $OE_VERSION"
  sudo add-apt-repository -y "deb http://mirrors.kernel.org/ubuntu/ xenial main" 1>/dev/null
  # Manually setting GPG keys for the Xenial repository is required
  sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 40976EAF437D05B5 1>/dev/null
  sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 3B4FE6ACC0B21F32 1>/dev/null
fi
sudo apt-get update && sudo apt-get upgrade -y 1>/dev/null
#sudo apt-get install -y libpq-dev bc 1>/dev/null
# Required for building psycopg2 and python-ldap
sudo apt-get install -y gcc libpq-dev libsasl2-dev libldap2-dev libssl-dev bc 1>/dev/null
echo -e "${GREEN}OK.${NC} Operating system updated successfully."


#--------------------------------------------------
# Install PostgreSQL Server
#--------------------------------------------------
echo -e "\n---- Installing PostgreSQL Server ----"
if [ $INSTALL_POSTGRESQL_FOURTEEN = "True" ]; then
    echo -e "\n---- Installing postgreSQL V14 due to the user's choise ----"
    sudo curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc|sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
    sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
    sudo apt-get update 1>/dev/null
    sudo apt-get install -y postgresql-14 1>/dev/null
else
    echo -e "\n---- Installing the default postgreSQL version based on Linux version ----"
    sudo apt-get install -y postgresql postgresql-server-dev-all 1>/dev/null
fi
echo -e "${GREEN}OK.${NC} PostgreSQL Server installed successfully."
POSTGRES_VERSION=$(psql --version | awk '{print $3}')
echo -e "${YELLOW}PostgreSQL version:${NC} $POSTGRES_VERSION"

echo -e "\n---- Creating OdooO PostgreSQL User  ----"
sudo su - postgres -c "createuser -s $OE_USER" 2> /dev/null || true
echo -e "${GREEN}OK.${NC} Odoo postgresql user created."
echo -e "${YELLOW}PostgreSQL user:${NC} $OE_USER"

#--------------------------------------------------
# Install Dependencies
#--------------------------------------------------
echo "---- Ensuring server timezone data is up-to-date ----"
sudo apt-get install -y locales libc6 tzdata util-linux 1>/dev/null
sudo dpkg-reconfigure --frontend noninteractive tzdata
echo -e "${GREEN}OK.${NC} Timezone data updated."

#--------------------------------------------------
# Ubuntu 22.04 with venv requires home directory ownership
sudo mkdir -p $OE_HOME
#--------------------------------------------------
# Create user and directories
#--------------------------------------------------

echo -e "\n---- Create Odoo system user ----"
sudo adduser --system --quiet --shell=/bin/bash --home=$OE_HOME --gecos 'ODOO' --group $OE_USER
#The user should also be added to the sudo'ers group.
sudo adduser $OE_USER sudo
echo -e "${GREEN}OK.${NC} Odoo system user ${BLUE}$OE_USER ${NC} created."

echo -e "\n---- Create Log directory ----"
sudo mkdir /var/log/$OE_USER
sudo chown $OE_USER:$OE_USER /var/log/$OE_USER
sudo chown -R odoo:odoo /$OE_HOME
echo -e "${GREEN}OK.${NC} Log directory created at ${BLUE}/var/log/$OE_USER${NC}."

echo -e "\n--- Installing Python with correct version --"

# Verify and install Python versions
install_python() {
  local v=$1
  if ! command -v python${v} &>/dev/null; then
    sudo add-apt-repository -y ppa:deadsnakes/ppa  1>/dev/null
    sudo apt update 1>/dev/null
    sudo apt install -y python${v} python${v}-venv python${v}-dev 1>/dev/null
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
echo -e "${GREEN}OK.${NC} Python ${BLUE}$PYTHON_VER${NC} installed successfully."

if [ "$USE_PYTHON_VENV" = "True" ]; then
  echo -e "\n---- Creating Python virtual environment at ${BLUE}$OE_VENV${NC} ----"
  python${PYTHON_VER} -m venv $OE_VENV
  echo -e "${GREEN}OK.${NC} Python virtual environment created."

  echo -e "\n---- Checking Python version used in venv ----"
  VENV_PYTHON_VERSION=$($OE_VENV/bin/python3 --version)
  echo -e "${YELLOW}$VENV_PYTHON_VERSION${NC}"

  echo -e "\n---- Installing pip requirements in virtual environment ----"
  $OE_VENV/bin/pip install --quiet --upgrade pip
  $OE_VENV/bin/pip install --quiet wheel
  $OE_VENV/bin/pip install --quiet -r https://github.com/odoo/odoo/raw/${OE_VERSION}/requirements.txt
  echo -e "${GREEN}OK.${NC} pip requirements installed in virtual environment."
else
  echo -e "\n---- Installing pip requirements globally (no venv in use) ----"
  sudo -H pip3 install --quiet --break-system-packages -r https://github.com/odoo/odoo/raw/${OE_VERSION}/requirements.txt
  echo -e "${GREEN}OK.${NC} pip requirements installed globally."
fi

echo -e "\n---- Installing core system packages ----"
sudo apt-get install -y git python3-cffi build-essential wget python3-dev python3-venv python3-wheel plocate 1>/dev/null
sudo apt-get install -y libxslt-dev libzip-dev libldap2-dev libsasl2-dev python3-setuptools node-less 1>/dev/null
sudo apt-get install -y libpng-dev libjpeg-dev gdebi 1>/dev/null
echo -e "${GREEN}OK.${NC} Core system packages installed."

echo -e "\n---- Installing ${BLUE}NodeJS, NPM${NC} and ${BLUE}rtlcss${NC} for RTL stylesheet support ----"
sudo apt-get install -y nodejs npm 1>/dev/null
sudo npm install -g rtlcss 1>/dev/null
echo -e "${GREEN}OK.${NC} NodeJS, NPM and rtlcss installed."
echo -e "\nInstalled versions:"
echo -e "  ${BLUE}NodeJS${NC}   version: ${YELLOW}$(node -v)${NC}"
echo -e "  ${BLUE}NPM${NC}      version: ${YELLOW}$(npm -v)${NC}"
echo -e "  ${BLUE}rtlcss${NC}   version: ${YELLOW}$(rtlcss -v)${NC}"

#--------------------------------------------------
# Install Wkhtmltopdf if user has selected it
#--------------------------------------------------
if [ $INSTALL_WKHTMLTOPDF = "True" ]; then
  echo -e "\n---- Installing ${BLUE}wkhtmltopdf${NC} ----"

  #Pick up correct one from x64 & x32 versions:
  if [ "`getconf LONG_BIT`" == "64" ];then
      _url=$WKHTMLTOX_X64
  else
      _url=$WKHTMLTOX_X32
  fi
  if ! sudo wget -q $_url; then
    echo "Error: Failed to download wkhtmltopdf from $_url"
    exit 1
  fi

  if [[ $(lsb_release -r -s) == "22.04" ]]; then
    # Ubuntu 22.04 LTS needs a specific Stretch package of wkhtmltopdf
    if ! sudo wget -q https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6-1/wkhtmltox_0.12.6-1.stretch_amd64.deb; then
      echo "Error: Failed to download $_url"
      exit 1
    fi
    # Ubuntu 22.04 LTS requires libjpeg62-turbo for wkhtmltopdf, but that is not available in the default repositories.
    # Resolution: libjpeg-turbo8 is a drop-in replacement for libjpeg62-turbo.
    sudo apt install -y libjpeg-turbo8 1>/dev/null
    sudo gdebi -n wkhtmltox_0.12.6-1.stretch_amd64.deb 1>/dev/null
  else
      # For older versions of Ubuntu
    _deb_file=$(basename $_url)
    sudo apt install -y ./"$_deb_file" 1>/dev/null
    rm -f "$_deb_file"
  fi
  
  sudo ln -s /usr/local/bin/wkhtmltopdf /usr/bin
  sudo ln -s /usr/local/bin/wkhtmltoimage /usr/bin

  echo -e "${GREEN}OK.${NC} wkhtmltopdf installed."
  echo -e "\nInstalled version:"
  echo -e "  ${BLUE}wkhtmltopdf${NC} version: ${YELLOW}$(wkhtmltopdf -V | awk '{print $2}')${NC}"

else
  echo -e "${YELLOW}NOTE:${NC} wkhtmltopdf was not installed due to the user's choice."
fi



#--------------------------------------------------
# Install ODOO
#--------------------------------------------------
echo -e "\n==== Installing ODOO Server ===="
sudo git clone --quiet --depth 1 --branch $OE_VERSION https://www.github.com/odoo/odoo $OE_HOME_EXT/
echo -e "${NC}Odoo ${BLUE}$OE_VERSION source cloned from GitHub to ${OE_HOME_EXT}${NC}."

if [ $IS_ENTERPRISE = "True" ]; then
    # Odoo Enterprise install!
    sudo pip3 install psycopg2-binary pdfminer.six 1>/dev/null
    echo -e "\n--- Creating symlink for node"
    sudo ln -s /usr/bin/nodejs /usr/bin/node
    sudo su $OE_USER -c "mkdir $OE_HOME/enterprise"
    sudo su $OE_USER -c "mkdir $OE_HOME/enterprise/addons"
    echo -e "${GREEN}OK.${NC} Symlinks created."

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

    echo -e "\n${GREEN}OK.${NC} Added Enterprise code under $OE_HOME/enterprise/addons ----"
    echo -e "\n---- Installing Enterprise specific libraries ----"
    sudo -H pip3 install num2words ofxparse dbfread ebaysdk firebase_admin pyOpenSSL
    sudo npm install -g less 1>/dev/null
    sudo npm install -g less-plugin-clean-css 1>/dev/null
    echo -e "${GREEN}OK.${NC} Enterprise specific libraries installed."
fi

echo -e "\n---- Creating custom module directory ----"
sudo su $OE_USER -c "mkdir $OE_HOME/custom"
sudo su $OE_USER -c "mkdir $OE_HOME/custom/addons"
echo -e "${GREEN}OK.${NC} Custom module directory created at ${BLUE}$OE_HOME/custom/addons${NC}."

echo -e "\n---- Setting permissions on home folder ----"
sudo chown -R $OE_USER:$OE_USER $OE_HOME/*
echo -e "${GREEN}OK.${NC} Home folder permissions set."

echo -e "* Init server config file"

sudo touch /etc/${OE_CONFIG}.conf
echo -e "* Populating server config file"
sudo su root -c "printf '[options] \n; This is the password that allows database operations:\n' >> /etc/${OE_CONFIG}.conf"
if [ $GENERATE_RANDOM_PASSWORD = "True" ]; then
    echo -e "* Generating random admin password"
    OE_SUPERADMIN=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
fi
sudo su root -c "printf 'admin_passwd = ${OE_SUPERADMIN}\n' >> /etc/${OE_CONFIG}.conf"

if [ "$(echo "$OE_VERSION > 11.0" | bc -l)" -eq 1 ]; then
  sudo su root -c "printf 'http_port = ${OE_PORT}\n' >> /etc/${OE_CONFIG}.conf"
else
  sudo su root -c "printf 'xmlrpc_port = ${OE_PORT}\n' >> /etc/${OE_CONFIG}.conf"
fi
sudo su root -c "printf 'logfile = /var/log/${OE_USER}/${OE_CONFIG}.log\n' >> /etc/${OE_CONFIG}.conf"
sudo su root -c "printf 'longpolling_port = $LONGPOLLING_PORT\n' >> /etc/${OE_CONFIG}.conf"

if [ $IS_ENTERPRISE = "True" ]; then
    sudo su root -c "printf 'addons_path=${OE_HOME}/enterprise/addons,${OE_HOME_EXT}/addons\n' >> /etc/${OE_CONFIG}.conf"
else
    sudo su root -c "printf 'addons_path=${OE_HOME_EXT}/addons,${OE_HOME}/custom/addons\n' >> /etc/${OE_CONFIG}.conf"
fi
sudo chown $OE_USER:$OE_USER /etc/${OE_CONFIG}.conf
sudo chmod 640 /etc/${OE_CONFIG}.conf

#Verifying longpolling port

if [ "$USE_PYTHON_VENV" = "True" ]; then
  sudo su root -c "echo 'sudo -u $OE_USER $OE_VENV/bin/python3 $OE_HOME_EXT/odoo-bin --config=/etc/${OE_CONFIG}.conf --longpolling-port=$LONGPOLLING_PORT' >> $OE_HOME_EXT/start.sh"
else
  sudo su root -c "echo 'sudo -u $OE_USER $OE_HOME_EXT/odoo-bin --config=/etc/${OE_CONFIG}.conf --longpolling-port=$LONGPOLLING_PORT' >> $OE_HOME_EXT/start.sh"
fi

sudo chmod 755 $OE_HOME_EXT/start.sh

#--------------------------------------------------
# Adding ODOO as a deamon (initscript)
#--------------------------------------------------

echo -e "* Create init file"
cat <<EOF > ~/$OE_CONFIG
#!/bin/sh
### BEGIN INIT INFO
# Provides: $OE_CONFIG
# Required-Start: \$remote_fs \$syslog
# Required-Stop: \$remote_fs \$syslog
# Should-Start: \$network
# Should-Stop: \$network
# Default-Start: 2 3 4 5
# Default-Stop: 0 1 6
# Short-Description: Enterprise Business Applications
# Description: ODOO Business Applications
### END INIT INFO
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/bin

# Setting up Python virtual environment if USE_PYTHON_VENV is True
# Additional options that are passed to the Daemon.

if [ "$USE_PYTHON_VENV" = "True" ]; then
  DAEMON=$OE_VENV/bin/python3
  DAEMON_OPTS="$OE_HOME_EXT/odoo-bin -c \$CONFIGFILE"
else
  DAEMON=$OE_HOME_EXT/odoo-bin
  DAEMON_OPTS="-c \$CONFIGFILE"
fi

NAME=$OE_CONFIG
DESC=$OE_CONFIG
# Specify the user name (Default: odoo).
USER=$OE_USER
# Specify an alternate config file (Default: /etc/openerp-server.conf).
CONFIGFILE="/etc/${OE_CONFIG}.conf"
# pidfile
PIDFILE=/var/run/\${NAME}.pid
# Additional options that are passed to the Daemon.
[ -x \$DAEMON ] || exit 0
[ -f \$CONFIGFILE ] || exit 0
checkpid() {
[ -f \$PIDFILE ] || return 1
pid=\`cat \$PIDFILE\`
[ -d /proc/\$pid ] && return 0
return 1
}
case "\${1}" in
start)
echo -n "Starting \${DESC}: "
start-stop-daemon --start --quiet --pidfile \$PIDFILE \
--chuid \$USER --background --make-pidfile \
--exec \$DAEMON -- \$DAEMON_OPTS
echo "\${NAME}."
;;
stop)
echo -n "Stopping \${DESC}: "
start-stop-daemon --stop --quiet --pidfile \$PIDFILE \
--oknodo
echo "\${NAME}."
;;
restart|force-reload)
echo -n "Restarting \${DESC}: "
start-stop-daemon --stop --quiet --pidfile \$PIDFILE \
--oknodo
sleep 1
start-stop-daemon --start --quiet --pidfile \$PIDFILE \
--chuid \$USER --background --make-pidfile \
--exec \$DAEMON -- \$DAEMON_OPTS
echo "\${NAME}."
;;
*)
#N=/etc/init.d/\$NAME
echo "Usage: \$NAME {start|stop|restart|force-reload}" >&2
exit 1
;;
esac
exit 0
EOF

echo -e "${GREEN}OK.${NC} Startup script created."

#--------------------------------------------------
# Install Nginx if needed
#--------------------------------------------------
if [ $INSTALL_NGINX = "True" ]; then
  echo -e "\n---- Installing and setting up Nginx ----"
  sudo apt install -y nginx 1>/dev/null
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
  sudo su root -c "printf 'proxy_mode = True\n' >> /etc/${OE_CONFIG}.conf"
  echo -e "${GREEN}OK.${NC} The Nginx server is up and running. Configuration can be found at ${BLUE}/etc/nginx/sites-available/$WEBSITE_NAME${NC}."
else
  echo "Nginx is not installed due to user's choise."
fi

#--------------------------------------------------
# Enable ssl with certbot
#--------------------------------------------------

if [ $INSTALL_NGINX = "True" ] && [ $ENABLE_SSL = "True" ] && [ $ADMIN_EMAIL != "odoo@example.com" ]  && [ $WEBSITE_NAME != "_" ];then
  echo -e "\n---- Installing ${BLUE}Certbot${NC} and enabling SSL/HTTPS ----"
  sudo apt-get update -y 1>/dev/null
  sudo apt install -y snapd 1>/dev/null
  sudo snap install core 1>/dev/null
  sudo snap refresh core 1>/dev/null
  sudo snap install --classic certbot 1>/dev/null
  sudo apt-get install -y python3-certbot-nginx 1>/dev/null
  sudo certbot --nginx -d $WEBSITE_NAME --noninteractive --agree-tos --email $ADMIN_EMAIL --redirect
  sudo service nginx reload
  echo -e "${GREEN}OK.${NC} Certbot installed and SSL/HTTPS enabled for ${BLUE}$WEBSITE_NAME${NC}."  
else
  echo "SSL/HTTPS is not enabled due to choice of the user or because of a misconfiguration!"
  if [ $ADMIN_EMAIL = "odoo@example.com" ]; then 
    echo -e "${RED}ERROR${NC} Certbot does not support registering with ${YELLOW}odoo@example.com${NC}. Please use a real e-mail address."
  fi
  if [ $WEBSITE_NAME = "_" ]; then
    echo -e "${RED}ERROR${NC} Website name is set as ${YELLOW}_${NC}. Cannot obtain SSL Certificate for _. Please use a real website address."
  fi
fi

echo -e "* Creating systemd service file for Odoo"

cat <<EOF | sudo tee /etc/systemd/system/$OE_CONFIG.service > /dev/null
[Unit]
Description=Odoo daemon
Requires=postgresql.service
After=network.target postgresql.service

[Service]
Type=simple
User=$OE_USER
Group=$OE_USER
ExecStart=$OE_VENV/bin/python3 $OE_HOME_EXT/odoo-bin --config=/etc/$OE_CONFIG.conf --longpolling-port=$LONGPOLLING_PORT
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

echo -e "* Starting Odoo Service"

echo -e "\n Waiting for Odoo to start and listen listening on port " $OE_PORT

# Wait for Odoo to start and listen on the specified port
for i in {1..5}; do
    if sudo lsof -i :$OE_PORT | grep LISTEN >/dev/null; then
        echo -e "${GREEN}OK.${NC} Odoo is now running and listening on port " $OE_PORT
        break
    fi
    sleep 1
done

if ! sudo lsof -i :$OE_PORT | grep LISTEN >/dev/null; then
    echo -e "${RED}ERROR:${NC} Odoo is not listening on port $OE_PORT after waiting up to 5 seconds."
    echo "please check logs at /var/log/${OE_USER}/${OE_CONFIG}.log"
    exit 1
fi

echo -e "\n---- Testing HTTP on longpolling port ----"

if curl -s --max-time 2 http://localhost:$LONGPOLLING_PORT > /dev/null; then
    echo -e "${GREEN}OK.${NC} Longpolling port $LONGPOLLING_PORT is responding."
else
    echo -e "${RED}ERROR.${NC} Longpolling port $LONGPOLLING_PORT does not respond."
fi


if pgrep -f odoo-bin >/dev/null; then
    echo "Odoo process is running."
else
    echo -e "${YELLOW}Warning${NC}: Odoo process not found even though port is open."
fi

if [ -f /var/log/${OE_USER}/${OE_CONFIG}.log ]; then
  echo -e "\n Latest Odoo log output tail:"
  echo "/var/log/${OE_USER}/${OE_CONFIG}.log"
  sudo tail -n 20 /var/log/${OE_USER}/${OE_CONFIG}.log
else
  echo -e "${RED}ERROR${NC}: No log file found at /var/log/${OE_USER}/${OE_CONFIG}.log"
  exit 1
fi

# Get server IP address (first non-loopback IPv4)
SERVER_IP=$(hostname -I | awk '{print $1}')

echo -e "${GREEN}-----------------------------------------------------------"
echo -e "Script done. Odoo is installed and running. Configuration summary:"
echo -e "-----------------------------------------------------------${NC}"

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
  echo -e " Public URL:  http://$DOMAIN_NAME/"
fi

echo -e "\n${GREEN} Access Odoo in your browser:${NC}"
echo -e " http://$SERVER_IP:$OE_PORT"

echo -e "${GREEN}-----------------------------------------------------------${NC}"

