#!/bin/bash

TMP_FOLDER=$(mktemp -d)
CONFIG_FILE="ellerium.conf"
DEFAULT_USER="ellerium-mn1"
DEFAULT_PORT=9850
DEFAULT_SSH_PORT=22
DAEMON_BINARY="elleriumd"
CLI_BINARY="ellerium-cli"
DAEMON_BINARY_FILE="/usr/local/bin/$DAEMON_BINARY"
CLI_BINARY_FILE="/usr/local/bin/$CLI_BINARY"
DAEMON_ZIP="https://github.com/ElleriumProject/Elleriumv2/releases/download/V2.0.0.0/linux_daemon.zip"
GITHUB_REPO="https://github.com/ElleriumProject/Elleriumv2"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

function checks() 
{
  if [[ $(lsb_release -d) != *16.04* ]]; then
    echo -e "${RED}You are not running Ubuntu 16.04. Installation is cancelled.${NC}"
    exit 1
  fi

  if [[ $EUID -ne 0 ]]; then
     echo -e "${RED}$0 must be run as root.${NC}"
     exit 1
  fi

  if [ -n "$(pidof $DAEMON_BINARY)" ]; then
    echo -e "The Ellerium daemon is already running. Ellerium does not support multiple masternodes on one host."
    NEW_NODE="n"
    clear
  else
    NEW_NODE="new"
  fi
}

function prepare_system() 
{
  clear
  echo -e "Checking if swap space is required."
  PHYMEM=$(free -g | awk '/^Mem:/{print $2}')
  
  if [ "$PHYMEM" -lt "2" ]; then
    SWAP=$(swapon -s get 1 | awk '{print $1}')
    if [ -z "$SWAP" ]; then
      echo -e "${GREEN}Server is running without a swap file and less than 2G of RAM, creating a 2G swap file.${NC}"
      dd if=/dev/zero of=/swapfile bs=1024 count=2M
      chmod 600 /swapfile
      mkswap /swapfile
      swapon -a /swapfile
    else
      echo -e "${GREEN}Swap file already exists.${NC}"
    fi
  else
    echo -e "${GREEN}Server is running with at least 2G of RAM, no swap file needed.${NC}"
  fi
  
  echo -e "${GREEN}Updating package manager${NC}."
  apt update
  
  echo -e "${GREEN}Upgrading existing packages, it may take some time to finish.${NC}"
  DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -y -qq upgrade 
  
  echo -e "${GREEN}Installing all dependencies for the Ellerium coin master node, it may take some time to finish.${NC}"
  apt install -y software-properties-common
  apt-add-repository -y ppa:bitcoin/bitcoin
  apt update
  apt install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
    make software-properties-common build-essential libtool autoconf libssl-dev libboost-dev libboost-chrono-dev libboost-filesystem-dev \
    libboost-program-options-dev libboost-system-dev libboost-test-dev libboost-thread-dev sudo automake git wget pwgen curl \
    bsdmainutils libdb4.8-dev libdb4.8++-dev libzmq3-dev libminiupnpc-dev libgmp3-dev ufw fail2ban htop unzip
  clear
  
  if [ "$?" -gt "0" ]; then
      echo -e "${RED}Not all of the required packages were installed correctly.\n"
      echo -e "Try to install them manually by running the following commands:${NC}\n"
      echo -e "apt update"
      echo -e "apt -y install software-properties-common"
      echo -e "apt-add-repository -y ppa:bitcoin/bitcoin"
      echo -e "apt update"
      echo -e "apt install -y make software-properties-common build-essential libtool autoconf libssl-dev libboost-dev libboost-chrono-dev libboost-filesystem-dev \
    libboost-program-options-dev libboost-system-dev libboost-test-dev libboost-thread-dev sudo automake git wget pwgen curl \
    bsdmainutils libdb4.8-dev libdb4.8++-dev libzmq3-dev libminiupnpc-dev libgmp3-dev ufw fail2ban htop unzip"
   exit 1
  fi

  clear
}

function deploy_binary() 
{
  if [ -f $DAEMON_BINARY_FILE ]; then
    echo -e "${GREEN}Ellerium daemon binary file already exists, using binary from $DAEMON_BINARY_FILE.${NC}"
  else
    cd $TMP_FOLDER

    archive=linux.walletV6.1.1.zip

    echo -e "${GREEN}Downloading $DAEMON_ZIP and deploying the Ellerium service.${NC}"
    wget $DAEMON_ZIP -O $archive >/dev/null 2>&1

    unzip $archive -d . >/dev/null 2>&1
    rm $archive

    cp "./daemon/elleriumd" /usr/local/bin/ >/dev/null 2>&1
    cp "./daemon/ellerium-cli" /usr/local/bin/ >/dev/null 2>&1

    chmod +x /usr/local/bin/ellerium*;

    cd
  fi
}

function enable_firewall() 
{
  echo -e "${GREEN}Setting up firewall to allow access on port $DAEMON_PORT.${NC}"

  apt install ufw -y >/dev/null 2>&1

  ufw disable >/dev/null 2>&1
  ufw allow $DAEMON_PORT/tcp comment "Ellerium Masternode port" >/dev/null 2>&1
  ufw allow $[DAEMON_PORT+1]/tcp comment "Ellerium Masernode RPC port" >/dev/null 2>&1
  
  ufw allow $SSH_PORTNUMBER/tcp comment "Custom SSH port" >/dev/null 2>&1
  ufw limit $SSH_PORTNUMBER/tcp >/dev/null 2>&1

  ufw logging on >/dev/null 2>&1
  ufw default deny incoming >/dev/null 2>&1
  ufw default allow outgoing >/dev/null 2>&1

  echo "y" | ufw enable >/dev/null 2>&1

  echo -e "${GREEN}Setting up fail2ban for additional server security."
  systemctl enable fail2ban >/dev/null 2>&1
  systemctl start fail2ban >/dev/null 2>&1
}

function add_daemon_service() 
{
  cat << EOF > /etc/systemd/system/$USER_NAME.service
[Unit]
Description=Ellerium deamon service
After=network.target
[Service]
Type=forking
User=$USER_NAME
Group=$USER_NAME
WorkingDirectory=$DATA_DIR
ExecStart=$DAEMON_BINARY_FILE -datadir=$DATA_DIR -daemon
ExecStop=$CLI_BINARY_FILE -datadir=$DATA_DIR stop
Restart=always
PrivateTmp=true
TimeoutStopSec=60s
TimeoutStartSec=10s
StartLimitInterval=120s
StartLimitBurst=5
  
[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  sleep 3

  echo -e "${GREEN}Starting the Ellerium service from $DAEMON_BINARY_FILE on port $DAEMON_PORT.${NC}"
  systemctl start $USER_NAME.service >/dev/null 2>&1
  
  echo -e "${GREEN}Enabling the service to start on reboot.${NC}"
  systemctl enable $USER_NAME.service >/dev/null 2>&1

  if [[ -z $(pidof $DAEMON_BINARY) ]]; then
    echo -e "${RED}The Ellerium masternode service is not running${NC}. You should start by running the following commands as root:"
    echo "systemctl start $USER_NAME.service"
    echo "systemctl status $USER_NAME.service"
    echo "less /var/log/syslog"
    exit 1
  fi
}

function ask_port() 
{
  read -e -p "$(echo -e $YELLOW Enter a port to run the Ellerium service on: $NC)" -i $DEFAULT_PORT DAEMON_PORT
}

function ask_user() 
{  
  read -e -p "$(echo -e $YELLOW Enter a new username to run the Ellerium service as: $NC)" -i $DEFAULT_USER USER_NAME

  if [ -z "$(getent passwd $USER_NAME)" ]; then
    useradd -m $USER_NAME
    USER_PASSWORD=$(pwgen -s 12 1)
    echo "$USER_NAME:$USER_PASSWORD" | chpasswd

    home_dir=$(sudo -H -u $USER_NAME bash -c 'echo $HOME')
    DATA_DIR="$home_dir/.ellerium"
        
    mkdir -p $DATA_DIR
    chown -R $USER_NAME: $DATA_DIR >/dev/null 2>&1
    
    sudo -u $USER_NAME bash -c : && RUNAS="sudo -u $USER_NAME"
  else
    clear
    echo -e "${RED}User already exists. Please enter another username.${NC}"
    ask_user
  fi
}

function check_port() 
{
  declare -a PORTS

  PORTS=($(netstat -tnlp | awk '/LISTEN/ {print $4}' | awk -F":" '{print $NF}' | sort | uniq | tr '\r\n'  ' '))
  ask_port

  while [[ ${PORTS[@]} =~ $DAEMON_PORT ]] || [[ ${PORTS[@]} =~ $[DAEMON_PORT+1] ]]; do
    clear
    echo -e "${RED}Port in use, please choose another port:${NF}"
    ask_port
  done
}

function ask_ssh_port()
{
  read -e -p "$(echo -e $YELLOW Enter a port for SSH connections to your VPS: $NC)" -i $DEFAULT_SSH_PORT SSH_PORTNUMBER

  sed -i "s/[#]\{0,1\}[ ]\{0,1\}Port [0-9]\{2,\}/Port ${SSH_PORTNUMBER}/g" /etc/ssh/sshd_config
  systemctl reload sshd
}

function create_config() 
{
  RPCUSER=$(pwgen -s 8 1)
  RPCPASSWORD=$(pwgen -s 15 1)
  cat << EOF > $DATA_DIR/$CONFIG_FILE
rpcuser=$RPCUSER
rpcpassword=$RPCPASSWORD
rpcallowip=127.0.0.1
rpcport=$[DAEMON_PORT+1]
listen=1
server=1
daemon=1
staking=1
port=$DAEMON_PORT
addnode=45.32.155.75
addnode=45.77.230.28
addnode=89.188.110.239
addnode=92.255.26.86
addnode=95.183.13.34
addnode=80.211.151.201
addnode=80.211.220.226
addnode=80.211.181.227
addnode=80.211.238.252
addnode=212.237.7.29
EOF
}

function create_key() 
{
  read -e -p "$(echo -e $YELLOW Enter your master nodes private key. Leave it blank to generate a new private key.$NC)" PRIV_KEY

  if [[ -z "$PRIV_KEY" ]]; then
    sudo -u $USER_NAME $DAEMON_BINARY_FILE -datadir=$DATA_DIR -daemon >/dev/null 2>&1
    sleep 5

    if [ -z "$(pidof $DAEMON_BINARY)" ]; then
    echo -e "${RED}Ellerium deamon couldn't start, could not generate a private key. Check /var/log/syslog for errors.${NC}"
    exit 1
    fi

    PRIV_KEY=$(sudo -u $USER_NAME $CLI_BINARY_FILE -datadir=$DATA_DIR masternode genkey) 
    sudo -u $USER_NAME $CLI_BINARY_FILE -datadir=$DATA_DIR stop >/dev/null 2>&1
  fi
}

function update_config() 
{
  DAEMON_IP=$(ip route get 1 | awk '{print $NF;exit}')
  cat << EOF >> $DATA_DIR/$CONFIG_FILE
logtimestamps=1
maxconnections=256
masternode=1
masternodeaddr=$DAEMON_IP:$DAEMON_PORT
masternodeprivkey=$PRIV_KEY
EOF
  chown $USER_NAME: $DATA_DIR/$CONFIG_FILE >/dev/null
}

function add_log_truncate()
{
  LOG_FILE="$DATA_DIR/debug.log";

  mkdir ~/.ellerium >/dev/null 2>&1
  cat << EOF >> ~/.ellerium/clearlog-$USER_NAME.sh
/bin/date > $LOG_FILE
EOF

  chmod +x ~/.ellerium/clearlog-$USER_NAME.sh

  if ! crontab -l | grep "~/ellerium/clearlog-$USER_NAME.sh"; then
    (crontab -l ; echo "0 0 */2 * * ~/.ellerium/clearlog-$USER_NAME.sh") | crontab -
  fi
}

function show_output() 
{
 echo
 echo -e "================================================================================================================================"
 echo
 echo -e "Your Ellerium coin master node is up and running." 
 echo -e " - it is running as user ${GREEN}$USER_NAME${NC} and it is listening on port ${GREEN}$DAEMON_PORT${NC} at your VPS address ${GREEN}$DAEMON_IP${NC}."
 echo -e " - the ${GREEN}$USER_NAME${NC} password is ${GREEN}$USER_PASSWORD${NC}"
 echo -e " - the Ellerium configuration file is located at ${GREEN}$DATA_DIR/$CONFIG_FILE${NC}"
 echo -e " - the masternode privkey is ${GREEN}$PRIV_KEY${NC}"
 echo
 echo -e "You can manage your Ellerium service from the cmdline with the following commands:"
 echo -e " - ${GREEN}systemctl start $USER_NAME.service${NC} to start the service for the given user."
 echo -e " - ${GREEN}systemctl stop $USER_NAME.service${NC} to stop the service for the given user."
 echo
 echo -e "The installed service is set to:"
 echo -e " - auto start when your VPS is rebooted."
 echo -e " - clear the ${GREEN}$LOG_FILE${NC} log file every 2nd day."
 echo
 echo -e "You can interrogate your masternode using the following commands when logged in as $USER_NAME:"
 echo -e " - ${GREEN}${CLI_BINARY} stop${NC} to stop the daemon"
 echo -e " - ${GREEN}${DAEMON_BINARY} -daemon${NC} to start the daemon"
 echo -e " - ${GREEN}${CLI_BINARY} getinfo${NC} to retreive your nodes status and information"
 echo
 echo -e "You can run ${GREEN}htop${NC} if you want to verify the Ellerium service is running or to monitor your server."
 if [[ $SSH_PORTNUMBER -ne $DEFAULT_SSH_PORT ]]; then
 echo
 echo -e " ATTENTION: you have changed your SSH port, make sure you modify your SSH client to use port $SSH_PORTNUMBER so you can login."
 fi
 echo 
 echo -e "================================================================================================================================"
 echo
}

function setup_node() 
{
  ask_user
  ask_ssh_port
  check_port
  create_config
  create_key
  update_config
  enable_firewall
  add_daemon_service
  add_log_truncate
  show_output
}

clear

echo
echo -e "========================================================================================================="
echo -e "${GREEN}"
echo -e "                                        888888 88     88\"\"Yb"
echo -e "                                        88__   88     88__dP"
echo -e "                                        88\"\"   88     88\"\"\"" 
echo -e "                                        888888 88ood8 88" 
echo                          
echo -e "${NC}"
echo -e "This script will automate the installation of your Ellerium coin masternode and server configuration by"
echo -e "performing the following steps:"
echo
echo -e " - Create a swap file if VPS is < 2GB RAM for better performance"
echo -e " - Prepare your system with the required dependencies"
echo -e " - Obtain the latest Ellerium masternode files from the Ellerium GitHub repository"
echo -e " - Create a user and password to run the Ellerium masternode service"
echo -e " - Install the Ellerium masternode service"
echo -e " - Update your system with a non-standard SSH port (optional)"
echo -e " - Add DDoS protection using fail2ban"
echo -e " - Update the system firewall to only allow; SSH, the masternode ports and outgoing connections"
echo -e " - Add some scheduled tasks for system maintenance"
echo
echo -e " The files will be downloaded and installed from:"
echo -e " ${GREEN}${DAEMON_ZIP}${NC}"
echo
echo -e "The script will output ${YELLOW}questions${NC}, ${GREEN}information${NC} and ${RED}errors${NC}"
echo -e "When finished the script will show a summary of what has been done."
echo
echo -e "Script created by click2install"
echo -e " - GitHub: https://github.com/click2install/elleriumcoin"
echo -e " - Discord: click2install#9625"
echo -e " - BTC: 1DJdhFp6CiVZSBSsXcecp1FnuHXDcsYQPu"
echo 
echo -e "========================================================================================================="
echo
read -e -p "$(echo -e $YELLOW Do you want to continue? [Y/N] $NC)" CHOICE

if [[ ("$CHOICE" == "n" || "$CHOICE" == "N") ]]; then
  exit 1;
fi

checks

if [[ "$NEW_NODE" == "new" ]]; then
  prepare_system
  deploy_binary
  setup_node
else
    echo -e "${GREEN}The Ellerium daemon is already running. Ellerium does not support multiple masternodes on one host.${NC}"
  get_info
  exit 0
fi
