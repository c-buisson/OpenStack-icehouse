#!/bin/bash -ex

# Please run that script as root !
# This script was tested with Ubuntu Trusty 14.04 LTS

# Passwords and variables, please edit them if needed!
nova_password="stack0n"
rabbit_password="stack0r"
ip_controller=""

if [ -z "$ip_controller" ]; then echo "Please set an IP for the controller node! Thanks!" && exit 1; fi

if [[ $EUID -ne 0 ]]; then
    echo "This script is design to be run as the root user!"
    echo -e "\e[31mLog in as the root user!"
    exit 1
fi

# You can choose between different virtualisation engines, like:
# kvm, qemu, lxc, uml and xen
virt="kvm"

# Environment variables
ip=`ifconfig eth0 |grep "inet addr" |awk '{print $2}' |awk -F: '{print $2}'`

echo -e "Let's install an \e[4mOpenStack Icehouse compute node! \e[0m########"
apt-get update && apt-get -y install ntp python-mysqldb ubuntu-cloud-keyring
cat > /etc/cron.daily/ntpdate << EOL
ntpdate $ip_controller
hwclock -w
EOL

add-apt-repository -y cloud-archive:icehouse
apt-get update && apt-get -y dist-upgrade

echo -e "\e[1;32mNOVA INSTALL \e[0m########"
sleep 2
export DEBIAN_FRONTEND=noninteractive
apt-get -q -y install nova-compute-$virt
rm /var/lib/nova/nova.sqlite
cat >> /etc/nova/nova.conf << EOL
auth_strategy = keystone
my_ip=$ip
#VNC
vnc_enabled=True
novncproxy_base_url=http://$ip_controller:6080/vnc_auto.html
vncserver_proxyclient_address=$ip
vncserver_listen=0.0.0.0
# GLANCE
glance_host=$ip_controller
rpc_backend = rabbit
rabbit_host = $ip_controller
rabbit_password = $rabbit_password
[keystone_authtoken]
auth_uri = http://$ip_controller:5000
auth_host = $ip_controller
auth_port = 35357
auth_protocol = http
admin_tenant_name = service
admin_user = nova
admin_password = $nova_password
EOL

echo "RESTART NOVA-COMPUTE SERVICE... ########"
service nova-compute restart

echo -e "NOVA CONFIGURATION DONE! ########\n"

echo -e "This script took \e[4m$SECONDS seconds\e[0m seconds to finish!"
