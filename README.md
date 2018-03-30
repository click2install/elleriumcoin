# Ellerium Coin

Shell script to install an [Ellerium Masternode](https://bitcointalk.org/index.php?topic=2837413.0) on a Linux server running Ubuntu 16.04.


## Installation 
```
wget -q https://raw.githubusercontent.com/click2install/elleriumcoin/master/install-ellerium.sh  
bash install-ellerium.sh
```

Donations for the creation and maintenance of this script are welcome at:
&nbsp;

ELLERIUM: AS3ydEoyLE3AB1TfJpPYJccbNoLCHf8ttH

&nbsp;


## Multiple master nodes on one server
The script does not support installing multiple masternodes on the same host.

&nbsp;


## Running the script
When you run the script it will tell you what it will do on your system. Once completed there is a summary of the information you need to be aware of regarding your node setup which you can copy/paste to your local PC.

If you want to run the script before setting up the node in your cold wallet the script will generate a priv key for you to use, otherwise you can supply the privkey during the script execution.

&nbsp;

## Security
The script allows for a custom SSH port to be specified as well as setting up the required firewall rules to only allow inbound SSH and node communications, whilst blocking all other inbound ports and all outbound ports.

The [fail2ban](https://www.fail2ban.org/wiki/index.php/Main_Page) package is also used to mitigate DDoS attempts on your server.

Despite this script needing to run as `root` you should secure your Ubuntu server as normal with the following precautions:

 - disable password authentication
 - disable root login
 - enable SSH certificate login only

If the above precautions are taken you will need to `su root` before running the script.

&nbsp;

## Disclaimer
Whilst effort has been put into maintaining and testing this script, it will automatically modify settings on your Ubuntu server - use at your own risk. By downloading this script you are accepting all responsibility for any actions it performs on your server.

&nbsp;






