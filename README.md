# SocialSend Masternode EasyInstall script

## Installation

These scripts will work if SocialSend is running from "send" user. The script must be executed from "root" user or from some user in sudoers's list.

SSH to your VPS and clone the Github repository:

```bash
git clone https://github.com/SocialSend/easy_masternode.git && cd easy_masternode
```

Install your Masternode:

```bash
./mn_install.sh
```

Update your Masternode Binaries:

```bash
./mn_update.sh
```

Reload and unpack new bootstrap for your Masternode:

```bash
./mn_update_blocks.sh
```

