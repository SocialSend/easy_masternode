# SocialSend Masternode EasyInstall script

## Installation

These scripts will work if SocialSend is running from "send" user. The script must be executed from "root" user or from some user in sudoers's list.

### SSH to your VPS and clone the Github repository:

```bash
git clone https://github.com/SocialSend/easy_masternode.git && cd easy_masternode
```

### Install your Masternode:

```bash
sudo ./mn_install.sh
```

### Update your Masternode Binaries:
SocialSend should run from "send" user, if not, this script will create a new user "send" but you have to copy configuration file manually.
```bash
sudo ./mn_update.sh
```

### Reload and unpack new bootstrap for your Masternode:
This script will download bootstrap and unpack it to /home/send/.send/ folder.. Check that your masternode is running from "send" user.
```bash
./mn_update_blocks.sh
```

