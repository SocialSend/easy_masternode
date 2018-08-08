#!/bin/bash
################################################################################
### SocialSend MASTERNODE INSTALLATION SCRIPT v1.2.0
################################################################################


declare -r SSH_INBOUND_PORT=22
declare -r AUTODETECT_EXTERNAL_IP=`ifconfig | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p' | head -n 1`

declare -r MN_SWAPSIZE=2000
declare -r MN_USER="send"
declare -r MN_DAEMON=/usr/local/bin/sendd
declare -r MN_INBOUND_PORT=50050            #mainnet
#declare -r MN_INBOUND_PORT=51474           #testnet
declare -r MN_CONF_DIR=/home/${MN_USER}/.send
declare -r MN_CONF_FILE=${MN_CONF_DIR}/send.conf
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

declare -r RELEASE_VERSION="1.2.0"
declare -r RELEASE_BUILD=1

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


function add_firewal_rule() {
    output ""
    output "Adding new firewall rule"
    sudo ufw allow ${MN_INBOUND_PORT}/tcp       &>> ${SCRIPT_LOGFILE}
}


# compile
function compile() {
    output ""
    if [ ! -d ${SCRIPTPATH}/${CODE_DIR} ]; then
        mkdir -p ${SCRIPTPATH}/${CODE_DIR}              &>> ${SCRIPT_LOGFILE}
    else
        output "Deleting old Source Code.."
        sudo rm -R ${SCRIPTPATH}/${CODE_DIR}            &>> ${SCRIPT_LOGFILE}
        mkdir -p ${SCRIPTPATH}/${CODE_DIR}              &>> ${SCRIPT_LOGFILE}
    fi
    cd ${SCRIPTPATH}/${CODE_DIR}                        &>> ${SCRIPT_LOGFILE}
    git clone ${GIT_URL} -b ${RELEASE_VERSION_SRC} .    &>> ${SCRIPT_LOGFILE}
    cd ${SCRIPTPATH}/${CODE_DIR}                        &>> ${SCRIPT_LOGFILE}
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
    output ""
    cd $MN_CONF_DIR &>> ${SCRIPT_LOGFILE}
    rm -R blocks/ &>> ${SCRIPT_LOGFILE}
    rm -R chainstate/ &>> ${SCRIPT_LOGFILE}

    output "Downloading bootstrap.."
    wget https://www.dropbox.com/s/rxzq0ofafh0dfpb/bootstrap.zip?dl=0 -O bootstrap.zip &>> ${SCRIPT_LOGFILE}

    output "Unpacking bootstrap"
    unzip bootstrap.zip &>> ${SCRIPT_LOGFILE}
    sudo chown -R ${MN_USER}:${MN_USER} ${MN_CONF_DIR} &>> ${SCRIPT_LOGFILE}
    rm -rf bootstrap.zip &>> ${SCRIPT_LOGFILE}
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

#add_firewal_rule
compile
unpack_bootstrap
create_mn_user
create_config
launch_daemon
finish