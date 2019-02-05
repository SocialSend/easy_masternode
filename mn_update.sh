#!/bin/bash
################################################################################
### SocialSend MASTERNODE INSTALLATION SCRIPT v1.2.0
################################################################################


declare -r SSH_INBOUND_PORT=22
declare -r AUTODETECT_EXTERNAL_IP=`ifconfig | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p' | head -n 1`

declare -r MN_SWAPSIZE=2000
declare    MN_USER="send"
declare -r MN_DAEMON=/usr/local/bin/sendd
declare -r MN_INBOUND_PORT=50050            #mainnet
#declare -r MN_INBOUND_PORT=51474           #testnet
declare    MN_CONF_DIR=/home/${MN_USER}/.send
declare    MN_CONF_FILE=${MN_CONF_DIR}/send.conf
declare -r MN_RPCUSER=$(date +%s | sha256sum | base64 | head -c 10 ; echo)
declare -r MN_RPCPASS=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1`

declare -r DATE_STAMP="$(date +%y-%m-%d-%s)"
declare -r SCRIPTPATH=$( cd $(dirname ${BASH_SOURCE[0]}) > /dev/null; pwd -P )
declare -r MASTERPATH="$(dirname "${SCRIPTPATH}")"
declare -r SCRIPT_VERSION="v1.2.0"
declare -r SCRIPT_LOGFILE="/tmp/send_mn_setup_${DATE_STAMP}.log"

declare -r GIT_URL=https://github.com/SocialSend/SocialSend.git
declare -r RELEASE_VERSION_SRC="master"     #mainnet
#declare -r RELEASE_VERSION_SRC="Dev"       #testnet
declare -r CODE_DIR="SocialSend"

declare -r RELEASE_VERSION="1.2.0.3"
declare -r RELEASE_BUILD=1
declare    INSTALL_BOOTSTRAP=0
declare    FORCE_COMPILE=0

EXTERNAL_IP=${AUTODETECT_EXTERNAL_IP}


function output() {
    printf "$(tput bold)$(tput setab 0)$(tput setaf 7)"
    echo $1
    printf "$(tput sgr0)"
}

function displayError() {
    echo
    echo $1;
    echo
    exit 1;
}

function get_confirmation() {
    read -r -p "${1:-Are you sure? [y/N]} " response
    case "$response" in
        [yY][eE][sS]|[yY])
            true
            ;;
        *)
            false
            ;;
    esac
}

function get_user() {
    read -r -p "Is your masternode running as 'send' user? [y/n] " response
    case "$response" in
        [yY][eE][sS]|[yY])
            true
            ;;
        *)
            read -e -p "Enter the user: " MN_USER
            MN_CONF_DIR=/home/${MN_USER}/.send

            if [ ${MN_USER} = "root" ]; then
                MN_CONF_DIR=/root/.send
            fi

            MN_CONF_FILE=${MN_CONF_DIR}/send.conf
            false
            ;;
    esac
    if get_confirmation "Do you want to install bootstrap? [ YES/NO y/n ]"; then
        INSTALL_BOOTSTRAP=1
    fi
    if get_confirmation "Do you want to compile from source? [ YES/NO y/n ]"; then
        FORCE_COMPILE=1
    fi
    output "User: ${MN_USER}"
    output "Config File: ${MN_CONF_FILE}"
    output "Install Bootstrap: ${INSTALL_BOOTSTRAP}"
    output "Force Compile: ${FORCE_COMPILE}"
}

function add_firewal_rule() {
    output ""
    output "Adding new firewall rule"
    sudo ufw allow ${MN_INBOUND_PORT}/tcp       &>> ${SCRIPT_LOGFILE}
}

function install_node() {
    sudo killall sendd &>> ${SCRIPT_LOGFILE}

    cd ${SCRIPTPATH} &>> ${SCRIPT_LOGFILE}
    rm SEND-${RELEASE_VERSION}-linux64.zip  &>> ${SCRIPT_LOGFILE}
    output "Downloading binaries..."
    wget "https://github.com/SocialSend/SocialSend/releases/download/v1.2.0.3/SEND-LINUX64-CLI-v1.2.0.3.zip" -O SEND-${RELEASE_VERSION}-linux64.zip &>> ${SCRIPT_LOGFILE}
    if [ ! -f SEND-${RELEASE_VERSION}-linux64.zip ]; then
        output "Unable to download latest release. Trying to compile from source code..."
        compile
    else
        unzip SEND-${RELEASE_VERSION}-linux64.zip &>> ${SCRIPT_LOGFILE}
        chmod +x sendd send-cli &>> ${SCRIPT_LOGFILE}
        if [ ! -f ${SCRIPTPATH}/sendd ]; then
            output "Corrupted archive. Trying to compile from source code..."
            compile
        else    
            ./sendd -version &>> ${SCRIPT_LOGFILE}
            if [ $? -ne 1 ]; then
                output "Compiled binaries launch failed. Trying to compile from source code..."
                compile
            else
                sudo mv sendd /usr/local/bin/ &>> ${SCRIPT_LOGFILE}
                sudo mv send-cli /usr/local/bin/ &>> ${SCRIPT_LOGFILE}
                # if it's not available after onstallation, theres something wrong
                if [ ! -f ${MN_DAEMON} ]; then
                    output "Installation failed! Trying to complile from source code..."
                    compile
                else
                    output "Daemon installed successfully"
                fi
            fi
        fi
    fi
    
}
# install required packages
function install_packages() {
    output ""
    output "Installing required packages..."
    sudo apt-get -y install wget unzip pkg-config &>> ${SCRIPT_LOGFILE}
    sudo apt-get -y install build-essential autoconf automake libtool libboost-all-dev libgmp-dev libssl-dev libcurl4-openssl-dev git qtbase5-dev libzmq3-dev &>> ${SCRIPT_LOGFILE}
    sudo add-apt-repository -y ppa:bitcoin/bitcoin  &>> ${SCRIPT_LOGFILE}
    sudo apt-get -y update  &>> ${SCRIPT_LOGFILE}
    sudo apt-get -y install libdb4.8-dev libdb4.8++-dev  &>> ${SCRIPT_LOGFILE}
    
    # only for 18.04 // openssl
    if [[ "${VERSION_ID}" == "18.04" ]] ; then
       sudo apt-get -qqy -o=Dpkg::Use-Pty=0 -o=Acquire::ForceIPv4=true install libssl1.0-dev &>> ${SCRIPT_LOGFILE}
    fi
}

# compile
function compile() {
    output ""
    if [ ! -d ${SCRIPTPATH}/${CODE_DIR} ]; then
        mkdir -p ${SCRIPTPATH}/${CODE_DIR}              &>> ${SCRIPT_LOGFILE}
        install_packages
        cd ${SCRIPTPATH}/${CODE_DIR}                        &>> ${SCRIPT_LOGFILE}
        git clone ${GIT_URL} -b ${RELEASE_VERSION_SRC} .    &>> ${SCRIPT_LOGFILE}
    else
        cd ${SCRIPTPATH}/${CODE_DIR}                        &>> ${SCRIPT_LOGFILE}
        git pull
    fi
    
    
    output "Checking out release version: c"
    git checkout ${RELEASE_VERSION_SRC}                 &>> ${SCRIPT_LOGFILE}

    chmod u+x share/genbuild.sh &>> ${SCRIPT_LOGFILE}
    chmod u+x src/leveldb/build_detect_platform &>> ${SCRIPT_LOGFILE}
    chmod u+x ./autogen.sh &>> ${SCRIPT_LOGFILE}

    output "Preparing to build..."
    ./autogen.sh &>> ${SCRIPT_LOGFILE}
    if [ $? -ne 0 ]; then displayError "Pre-build failed!"; fi

    output "Configuring build options..."
    ./configure --disable-dependency-tracking --disable-tests --disable-bench --with-gui=no --disable-gui-tests --with-miniupnpc=no &>> ${SCRIPT_LOGFILE}
    if [ $? -ne 0 ]; then displayError "Configuring failed!"; fi

    output "Building SEND... this may take a few minutes..."
    sudo make &>> ${SCRIPT_LOGFILE}
    if [ $? -ne 0 ]; then displayError "Build failed!"; fi

    output "Building Finished.. Removing old binaries.."
    sudo killall sendd &>> ${SCRIPT_LOGFILE}
    sudo rm -R /usr/local/bin/send* &>> ${SCRIPT_LOGFILE}

    output "Installing SEND..."
    sudo make install &>> ${SCRIPT_LOGFILE}
    if [ $? -ne 0 ]; then displayError "Installation failed!"; fi
   
    # if it's not available after compilation, theres something wrong
    if [ ! -f ${MN_DAEMON} ]; then
        displayError "COMPILATION FAILED!"
    fi

    output "Daemon compiled and installed successfully"
}


function unpack_bootstrap() {
    if [ $INSTALL_BOOTSTRAP -eq 1 ]; then
        output ""
        cd $MN_CONF_DIR &>> ${SCRIPT_LOGFILE}
        rm -R blocks/ &>> ${SCRIPT_LOGFILE}
        rm -R chainstate/ &>> ${SCRIPT_LOGFILE}
        rm peers.dat &>> ${SCRIPT_LOGFILE}

        output "Downloading bootstrap.."
        wget https://www.dropbox.com/s/rxzq0ofafh0dfpb/bootstrap.zip?dl=0 -O bootstrap.zip &>> ${SCRIPT_LOGFILE}

        output "Unpacking bootstrap"
        unzip -o bootstrap.zip &>> ${SCRIPT_LOGFILE}
        sudo chown -R ${MN_USER}:${MN_USER} ${MN_CONF_DIR} &>> ${SCRIPT_LOGFILE}
        rm -rf bootstrap.zip &>> ${SCRIPT_LOGFILE}
    fi
}

# creates mn user
function create_mn_user() {
    output ""
    if id "${MN_USER}" >/dev/null 2>&1; then
        output "MN user exists already, do nothing"
    else
        output "Adding new MN user ${MN_USER}"
        sudo adduser --disabled-password --gecos "" ${MN_USER} &>> ${SCRIPT_LOGFILE}
    fi
}

function create_config() {
    output ""
    output "Creating masternode config"

    if [ ! -d "$MN_CONF_DIR" ]; then sudo mkdir $MN_CONF_DIR; fi
    if [ $? -ne 0 ]; then displayError "Unable to create config directory!"; fi
    
    if [ ! -f ${MN_CONF_FILE} ]; then
        output "Creating MN config file.."
        sudo bash -c "cat > ${MN_CONF_FILE} <<-EOF
        listen=1
        server=1
        daemon=1
        masternode=1
        rpcbind=127.0.0.1
        rpcconnect=127.0.0.1
        rpcallowip=127.0.0.1
        rpcuser=${MN_RPCUSER}
        rpcpassword=${MN_RPCPASS}
        maxconnections=256
        EOF"

        sudo chown -R ${MN_USER}:${MN_USER} ${MN_CONF_DIR} &>> ${SCRIPT_LOGFILE}
    else
        output "MN config file exist.."
    fi
}

function launch_daemon() {
    output ""
    output "Launching daemon..."

    sudo -u ${MN_USER} -H sendd &>> ${SCRIPT_LOGFILE}
}


function finish() {
    output ""
    output "Success! Your SocialSend masternode has been updated"
    exit 0
}



clear
get_user
#add_firewal_rule
#compile
if [ $FORCE_COMPILE -eq 1 ]; then
    compile
else
    install_node
fi
unpack_bootstrap
#create_mn_user
#create_config
launch_daemon
finish