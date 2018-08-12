# SocialSend Masternode EasyInstall script

## Installation

These scripts will work if SocialSend is running from "send" user. The script must be executed from "root" user or from some user in sudoers's list.

### SSH to your VPS and clone the Github repository:

```bash
git clone https://github.com/SocialSend/easy_masternode.git && cd easy_masternode
```

### Install your Masternode:
Download and compile binaries and install dependecies. This script is only for the first time that you install Send core on VPS. If you want to update your masternode just use mn_update.sh script.

```bash
sudo ./mn_install.sh
```

### Update your Masternode Binaries:
First, this script will ask you the user who run the masternode, by default "send". Then it will ask you if you want to download bootstrap, if you masternode is synced you should not download bootstrap. After that, script will work alone and when it finished it will start again your masternode. 
In general, you masternode will not be "MISSING" after update, but please when it finish check on control wallet if your masternode is still running, if not, start it by "START ALIAS".

```bash
sudo ./mn_update.sh
```

### Reload and unpack new bootstrap for your Masternode:
At the beggining this script will ask you the user who run the masternode, by default "send", if not, enter the correct user. After download and unpack bootstrap it will start your masternode again.

```bash
./mn_update_blocks.sh
```

