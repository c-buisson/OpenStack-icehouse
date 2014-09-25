#!/bin/bash -ex

# Please run that script as root !
# This script was tested with Ubuntu Trusty 14.04 LTS

#This script assume that Cinder-api and Cinder-scheduler are running on the controller node.
#It also assumes that this server has 2 disks: /dev/sda and /dev/sdb.

# Passwords and variables, please edit them if needed!
cinder_password="stack0c"
rabbitmq_password="stack0r"
ip_controller=""

if [[ $EUID -ne 0 ]]; then
    echo "This script is design to be run as the root user!"
    echo -e "\e[31mLog in as the root user!"
    exit 1
fi

if [ -z "$ip_controller" ]; then echo "Please set an IP for the controller node! Thanks!" && exit 1; fi

# Environment variables
ip=`ifconfig eth0 |grep "inet addr" |awk '{print $2}' |awk -F: '{print $2}'`

echo -e "Let's install an \e[4mOpenStack Icehouse cinder-volume node! \e[0m########"
apt-get update && apt-get -y install ntp python-mysqldb ubuntu-cloud-keyring
cat > /etc/cron.daily/ntpdate << EOL
ntpdate $ip_controller
hwclock -w
EOL

add-apt-repository -y cloud-archive:icehouse
apt-get update && apt-get -y dist-upgrade

echo -e "\e[1;32mCINDER INSTALL \e[0m########"
sleep 2
apt-get -y install cinder-volume lvm2
cat >> /etc/cinder/cinder.conf << EOL
rpc_backend = rabbit
rabbit_host = $ip_controller
rabbit_port = 5672
rabbit_userid = guest
rabbit_password = $rabbitmq_passowrd
glance_host = $ip_controller
[keystone_authtoken]
auth_uri = http://$ip_controller:5000
auth_host = $ip_controller
auth_port = 35357
auth_protocol = http
admin_tenant_name = service
admin_user = cinder
admin_password = $cinder_password
[database]
connection = mysql://cinder:$cinder_password@$ip_controller/cinder
EOL

echo "CREATING LVM PHYSICAL VOLUME ########"
pvcreate /dev/sdb
vgcreate cinder-volumes /dev/sdb

echo "EDIT LVM.CONF FILE ########"
sed -i 's/filter = \[ "a\/.*\/" \]/filter = \[ "a\/sda1\/", "a\/sdb1\/", "r\/.*\/"\]/g' /etc/lvm/lvm.conf

echo "RESTART CINDER-VOLUME AND TGT SERVICES... ########"
service cinder-volume restart
service tgt restart

echo -e "CINDER CONFIGURATION DONE! ########\n"

echo -e "This script took \e[4m$SECONDS seconds\e[0m to finish!"
