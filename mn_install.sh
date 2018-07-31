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

# checking OS
function check_distro() {
    # currently only for Ubuntu 14.04 & 16.04 & 18.04
    if [[ -r /etc/os-release ]]; then
        . /etc/os-release
        if [[ "${VERSION_ID}" != "14.04" ]] && [[ "${VERSION_ID}" != "16.04" ]] && [[ "${VERSION_ID}" != "17.10" ]] && [[ "${VERSION_ID}" != "18.04" ]] ; then
            displayError "This script only supports Ubuntu 14.04 & 16.04 & 17.10 & 18.04 LTS, exiting."
        fi
    else
        displayError "This script only supports Ubuntu 14.04 & 16.04 & 17.10 & 18.04 LTS, exiting."
    fi
}

# get input
function get_input() {
    output ""
    output ""

    output "[ SocialSend MASTERNODE INSTALLATION SCRIPT ${SCRIPT_VERSION} ]"

    output ""
    output ""

    read -e -p "Enter your Masternode Private key (a string generated by 'masternode genkey' command) : " MN_PKEY

    if ! get_confirmation "Auto-detected server IP address: ${AUTODETECT_EXTERNAL_IP} . Is it correct? [ YES/NO y/n ]"; then
        read -e -p "Enter correct server IP address: " EXTERNAL_IP
    fi

    output ""
    output "Masternode Private Key: ${MN_PKEY}"
    output "Masternode IP address: ${EXTERNAL_IP}"
    get_confirmation "Make sure you double check before continue! Is it ok? [ YES/NO y/n ]" || exit 0
}

# update
function update_system() {
    output ""
    output "Updating system..."
    
    sudo apt-get -y update   &>> ${SCRIPT_LOGFILE}
    # sudo apt-get -y upgrade  &>> ${SCRIPT_LOGFILE}
    sudo apt-get -y autoremove  &>> ${SCRIPT_LOGFILE}
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

# creates and activates a swapfile since VPS servers often do not have enough RAM for compilation
function swaphack() {
    output ""
    if [ $(free | awk '/^Swap:/ {exit !$2}') ] || [ ! -f "/var/mn_swap.img" ];then
        output "No proper swap, creating it"
        sudo rm -f /var/mn_swap.img
        sudo dd if=/dev/zero of=/var/mn_swap.img bs=1024k count=${MN_SWAPSIZE} &>> ${SCRIPT_LOGFILE}
        sudo chmod 0600 /var/mn_swap.img
        sudo mkswap /var/mn_swap.img &>> ${SCRIPT_LOGFILE}
        sudo swapon /var/mn_swap.img &>> ${SCRIPT_LOGFILE}
        sudo echo '/var/mn_swap.img none swap sw 0 0' | tee -a /etc/fstab &>> ${SCRIPT_LOGFILE}
        sudo echo 'vm.swappiness=10' | tee -a /etc/sysctl.conf               &>> ${SCRIPT_LOGFILE}
        sudo echo 'vm.vfs_cache_pressure=50' | tee -a /etc/sysctl.conf       &>> ${SCRIPT_LOGFILE}
    else
        output "All good, we have a swap"
    fi
}

# firewall
function configure_firewall() {
    output ""
    output "Configuring firewall rules"
    sudo ufw default deny                          &>> ${SCRIPT_LOGFILE}
    sudo ufw logging on                            &>> ${SCRIPT_LOGFILE}
    sudo ufw allow ${SSH_INBOUND_PORT}/tcp         &>> ${SCRIPT_LOGFILE}
    sudo ufw allow ${MN_INBOUND_PORT}/tcp       &>> ${SCRIPT_LOGFILE}
    sudo ufw limit OpenSSH                         &>> ${SCRIPT_LOGFILE}
    sudo ufw --force enable                        &>> ${SCRIPT_LOGFILE}
}

function add_firewal_rule() {
    output ""
    output "Adding new firewall rule"
    sudo ufw allow ${MN_INBOUND_PORT}/tcp       &>> ${SCRIPT_LOGFILE}
}

# install
function install_node() {
    sudo killall sendd &>> ${SCRIPT_LOGFILE}
    sudo rm -rf ${MN_CONF_DIR}/* &>> ${SCRIPT_LOGFILE}

    if [ ! -f ${MN_DAEMON} ]; then
        cd ${SCRIPTPATH} &>> ${SCRIPT_LOGFILE}
        wget "https://github.com/SocialSend/SocialSend/releases/download/${RELEASE_VERSION}.${RELEASE_BUILD}/SEND-${RELEASE_VERSION}-linux.tar.gz" -O SEND-${RELEASE_VERSION}-linux64.tar.gz &>> ${SCRIPT_LOGFILE}
        if [ ! -f SEND-${RELEASE_VERSION}-linux64.tar.gz ]; then
            output "Unable to download latest release. Trying to compile from source code..."
            compile
        else
            tar -xvf SEND-${RELEASE_VERSION}-linux.tar.gz &>> ${SCRIPT_LOGFILE}
            if [ ! -f ${SCRIPTPATH}/send-${RELEASE_VERSION}/bin/sendd ]; then
                output "Corrupted archive. Trying to compile from source code..."
                compile
            else    
                cd send-${RELEASE_VERSION}/bin &>> ${SCRIPT_LOGFILE}
                ./sendd -version &>> ${SCRIPT_LOGFILE}
                if [ $? -ne 0 ]; then
                    output "Compiled binaries launch failed. Trying to compile from source code..."
                    compile
                else
                    sudo cp * /usr/local/bin/ &>> ${SCRIPT_LOGFILE}
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
    else
        output "Daemon already in place at ${MN_DAEMON}, not compiling"
    fi
}

# compile
function compile() {
    output ""
     # daemon not found compile it
    if [ ! -f ${MN_DAEMON} ]; then
            if [ ! -d ${SCRIPTPATH}/${CODE_DIR} ]; then
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

            output "Installing SEND..."
            sudo make install &>> ${SCRIPT_LOGFILE}
            if [ $? -ne 0 ]; then displayError "Installation failed!"; fi
    else
            output "Daemon already in place at ${MN_DAEMON}, not compiling"
    fi

    # if it's not available after compilation, theres something wrong
    if [ ! -f ${MN_DAEMON} ]; then
        displayError "COMPILATION FAILED!"
    fi

    output "Daemon compiled and installed successfully"
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
    
    sudo bash -c "cat > ${MN_CONF_FILE} <<-EOF
listen=1
server=1
daemon=1
masternode=1
masternodeprivkey=${MN_PKEY}
bind=${EXTERNAL_IP}
externalip=${EXTERNAL_IP}
rpcbind=127.0.0.1
rpcconnect=127.0.0.1
rpcallowip=127.0.0.1
rpcuser=${MN_RPCUSER}
rpcpassword=${MN_RPCPASS}
maxconnections=256
EOF"

    sudo chown -R ${MN_USER}:${MN_USER} ${MN_CONF_DIR} &>> ${SCRIPT_LOGFILE}
}

function unpack_bootstrap() {
    output ""
    output "Unpacking bootstrap"

    cd $MN_CONF_DIR &>> ${SCRIPT_LOGFILE}
    wget https://socialsend.io/res/blockchain.tar.gz &>> ${SCRIPT_LOGFILE}
    tar -xvf blockchain.tar.gz &>> ${SCRIPT_LOGFILE}
    sudo chown -R ${MN_USER}:${MN_USER} ${MN_CONF_DIR} &>> ${SCRIPT_LOGFILE}
    rm -rf blockchain.tar.gz &>> ${SCRIPT_LOGFILE}
}


function launch_daemon() {
    output ""
    output "Launching daemon..."

    sudo -u ${MN_USER} -H sendd &>> ${SCRIPT_LOGFILE}
}


function finish() {
    output ""
    output "Success! Your SocialSend masternode has started. Now update your Masternode.conf in your local wallet:"
    output "<MN-ALIAS> $EXTERNAL_IP:$MN_INBOUND_PORT $MN_PKEY <TX_ID> <TX_OUTPUT_INDEX>"
    exit 0
}



clear

check_distro
get_input
update_system
install_packages
swaphack
#configure_firewall
add_firewal_rule
install_node
create_mn_user
create_config
#unpack_bootstrap
launch_daemon
finish