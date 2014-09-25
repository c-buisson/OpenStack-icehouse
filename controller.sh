#!/bin/bash -ex

# Please run that script as root!
# This script was tested with Ubuntu Trusty 14.04 LTS

# This script will setup: Keystone, Glance, Nova: -api, -scheduler, -cert, -conductor, -consoleauth, -novncproxy (with basic settings), Cinder, Trove, Horizon and Euca2ools.

# Passwords, please edit them if needed!
admin_pass="mypass"
mysql_password="stack0m"
keystone_password="stack0k"
glance_password="stack0g"
nova_password="stack0n"
cinder_password="stack0c"
trove_password="stack0db"
token='stack0t'
rabbitmq_password='stack0r'

# Environment variables
ip=`ifconfig eth0 |grep "inet addr" |awk '{print $2}' |awk -F: '{print $2}'`
keystone_creds="--os-token=$token --os-endpoint=http://$ip:35357/v2.0"

if [[ $EUID -ne 0 ]]; then
    echo "This script has been designed to be run as the root user!"
    echo -e "\e[31mLog in as the root user!"
    exit 1
fi

echo -e "Let's install an \e[4mOpenStack Icehouse controller node! \e[0m########\n"
apt-get update
export DEBIAN_FRONTEND=noninteractive
apt-get -q -y install ntp python-mysqldb mysql-server htop git iotop rabbitmq-server ubuntu-cloud-keyring euca2ools curl
echo "UPDATE RABBITMQ PASSWORD"
rabbitmqctl change_password guest $rabbitmq_password
echo "CHANGE PASSWORD MYSQL ########"
mysqladmin -u root password $mysql_password
sed -i s,127.0.0.1,$ip,g /etc/mysql/my.cnf
sed -i s,'Basic Settings',"Basic Settings\ndefault-storage-engine = innodb\ninnodb_file_per_table\ncollation-server = utf8_general_ci\ninit-connect = 'SET NAMES utf8'\ncharacter-set-server = utf8\n",g /etc/mysql/my.cnf
service mysql restart
add-apt-repository -y cloud-archive:icehouse
apt-get update && apt-get -y dist-upgrade

echo -e "\e[1;32mCREATING MySQL DBs and USERS \e[0m########"
sleep 2
echo "CREATE KEYSTONE DATABASE ########"
mysql -uroot -p$mysql_password -e "CREATE DATABASE keystone"
mysql -uroot -p$mysql_password -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$keystone_password';"
mysql -uroot -p$mysql_password -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$keystone_password';"
echo "CREATE GLANCE DATABASE ########"
mysql -uroot -p$mysql_password -e "CREATE DATABASE glance"
mysql -uroot -p$mysql_password -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '$glance_password';"
mysql -uroot -p$mysql_password -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '$glance_password';"
echo "CREATE NOVA DATABASE ########"
mysql -uroot -p$mysql_password -e "CREATE DATABASE nova"
mysql -uroot -p$mysql_password -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '$nova_password';"
mysql -uroot -p$mysql_password -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '$nova_password';"
echo "CREATE CINDER DATABASE ########"
mysql -uroot -p$mysql_password -e "CREATE DATABASE cinder"
mysql -uroot -p$mysql_password -e "GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'localhost' IDENTIFIED BY '$cinder_password';"
mysql -uroot -p$mysql_password -e "GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'%' IDENTIFIED BY '$cinder_password';"
echo "CREATE TROVE DATABASE ########"
mysql -uroot -p$mysql_password -e "CREATE DATABASE trove"
mysql -uroot -p$mysql_password -e "GRANT ALL PRIVILEGES ON trove.* TO 'trove'@'localhost' IDENTIFIED BY '$trove_password';"
mysql -uroot -p$mysql_password -e "GRANT ALL PRIVILEGES ON trove.* TO 'trove'@'%' IDENTIFIED BY '$trove_password';"
echo "REMOVE ANONYMOUS USERS ########"
mysql -uroot -p$mysql_password -e "delete from user where user='';" mysql
echo -e "FLUSH MYSQL PRIVILEGES ########\n"
mysql -uroot -p$mysql_password -e "flush privileges"

echo -e "\e[1;32mKEYSTONE INSTALL \e[0m########"
sleep 2
apt-get -y install keystone python-keystone python-keystoneclient
sed -i s,'#admin_token=ADMIN',"admin_token=$token",g /etc/keystone/keystone.conf
sed -i s,'connection = sqlite:////var/lib/keystone/keystone.db',"connection = mysql://keystone:$keystone_password@$ip/keystone",g /etc/keystone/keystone.conf
echo "KEYSTONE DB_SYNC ########"
keystone-manage db_sync
service keystone restart
echo "SETUP KEYSTONE.... ########"
sleep 2

echo "CREATE ADMIN TENANT ########"
keystone $keystone_creds tenant-create --name=admin --description="Admin Tenant"
tenant_admin_id=`keystone $keystone_creds tenant-list |grep admin |awk '{print $2}'`
echo "CREATE SERVICE TENANT ########"
keystone $keystone_creds tenant-create --name=service --description="Service Tenant"
echo "CREATE ADMIN USER ########"
keystone $keystone_creds user-create --name=admin --pass=$admin_pass --email=clement@example.com
admin_user_id=`keystone $keystone_creds user-list |grep admin |awk '{print $2}'`
echo "CREATE ADMIN ROLE ########"
keystone $keystone_creds role-create --name=admin
echo "ASSIGN ADMIN USER TO ADMIN ROLE ########"
keystone $keystone_creds user-role-add --user=admin --tenant=admin --role=admin

echo "SETUP KEYSTONE SERVICE FOR KEYSTONE ########"
keystone_id=`keystone $keystone_creds service-create --name=keystone --type=identity --description="Keystone Identity Service" |grep -w id |awk '{print $4}'`
echo "SETUP KEYSTONE ENDPOINT ########"
keystone $keystone_creds endpoint-create --service-id=$keystone_id --publicurl=http://$ip:5000/v2.0 --internalurl=http://$ip:5000/v2.0 --adminurl=http://$ip:35357/v2.0
keystone $keystone_creds user-list
echo -e "KEYSTONE CONFIGURATION DONE! ########\n"

echo -e "\e[1;32mGLANCE INSTALL \e[0m########"
sleep 2
apt-get -y install glance python-glanceclient
glance_conf=( /etc/glance/glance-api.conf /etc/glance/glance-registry.conf )

for i in "${glance_conf[@]}"
do
sed -i s,'sqlite_db = /var/lib/glance/glance.sqlite',"connection = mysql://glance:$glance_password@$ip/glance",g $i
sed -i s,'auth_host = 127.0.0.1',"auth_uri = http://$ip:5000\nauth_host = $ip",g $i
sed -i s,%SERVICE_TENANT_NAME%,service,g $i
sed -i s,%SERVICE_USER%,glance,g $i
sed -i s,%SERVICE_PASSWORD%,$glance_password,g $i
sed -i s,'#flavor=','flavor=keystone',g $i
sed -i s,'bind_host = 0.0.0.0',"bind_host = $ip",g $i
sed -i s,'registry_host = 0.0.0.0',"registry_host = $ip",g $i
done

echo "GLANCE DB_SYNC ########"
glance-manage db_sync
echo "CREATE GLANCE USER IN KEYSTONE ########"
keystone $keystone_creds user-create --name=glance --pass=$glance_password --email=glance@example.com
echo "ADD ROLE ADMIN TO GLANCE USER ########"
keystone $keystone_creds user-role-add --user=glance --tenant=service --role=admin

echo "SETUP GLANCE SERVICE FOR KEYSTONE ########"
glance_id=`keystone $keystone_creds service-create --name=glance --type=image --description="Glance Image Service" |grep -w id |awk '{print $4}'`
echo "SETUP GLANCE ENDPOINT ########"
keystone $keystone_creds endpoint-create --service-id=$glance_id --publicurl=http://$ip:9292 --internalurl=http://$ip:9292 --adminurl=http://$ip:9292
echo "RESTART GLANCE-API AND REGISTRY SERVICES... ########"
service glance-registry restart
service glance-api restart

echo "ADD ENVIRONMENT VARIABLES ########"
cat >> /etc/environment << EOL
export OS_USERNAME=admin
export OS_PASSWORD=$admin_pass
export OS_TENANT_NAME=admin
export OS_AUTH_URL=http://$ip:35357/v2.0
export OS_SERVICE_ENDPOINT=http://$ip:35357/v2.0
export OS_SERVICE_TOKEN=$token
EOL

source /etc/environment
echo "ADD CIRROS TO GLANCE ########"
wget http://download.cirros-cloud.net/0.3.2/cirros-0.3.2-x86_64-disk.img
glance image-create --name="CirrOS 0.3.2" --disk-format=qcow2 --container-format=bare --is-public=true < cirros-0.3.2-x86_64-disk.img
glance --os-username=admin --os-password=$admin_pass --os-tenant-name=admin --os-auth-url=http://$ip:35357/v2.0 image-list
echo -e "GLANCE CONFIGURATION DONE! ########\n"

echo -e "\e[1;32mEUCA2OOLS SETUP \e[0m########"
sleep 2
echo "SETUP EC2 SERVICE FOR KEYSTONE ########"
euca2ool_id=`keystone $keystone_creds  service-create --name=ec2 --type=ec2 --description="EC2 Compatibility Layer" |grep -w id |awk '{print $4}'`
echo "SETUP EC2 ENDPOINT ########"
keystone $keystone_creds endpoint-create --service-id=$euca2ool_id --publicurl=http://$ip:8773/services/Cloud --internalurl=http://$ip:8773/services/Cloud --adminurl=http://$ip:8773/services/Admin
echo "GENERATE EC2 KEYS ########"
keystone $keystone_creds ec2-credentials-create --user-id $admin_user_id --tenant-id $tenant_admin_id
access_id=`keystone $keystone_creds ec2-credentials-list --user-id $admin_user_id |grep -v WARNING |grep -v \+ | awk '{print $4}' |grep -v access`
secret_id=`keystone $keystone_creds ec2-credentials-list --user-id $admin_user_id |grep -v WARNING |grep -v \+ | awk '{print $6}' |grep -v secret`
echo "EC2_ACCESS_KEY=$access_id" >> /etc/environment
echo "EC2_SECRET_KEY=$secret_id" >> /etc/environment
echo "EC2_URL=http://127.0.0.1:8773/services/Cloud" >> /etc/environment
echo -e "EUCA2OOLS CONFIGURATION DONE! ########\n"

echo -e "\e[1;32mNOVA INSTALL \e[0m########"
sleep 2

apt-get -y install nova-api nova-cert nova-conductor nova-consoleauth nova-novncproxy nova-scheduler python-novaclient
echo "CREATE NOVA USER IN KEYSTONE ########"
keystone $keystone_creds user-create --name=nova --pass=$nova_password --email=nova@example.com
echo "ADD ROLE ADMIN TO NOVA USER ########"
keystone $keystone_creds user-role-add --user=nova --tenant=service --role=admin

sed -i s,'auth_host = 127.0.0.1',"auth_host = $ip",g /etc/nova/api-paste.ini
sed -i s,%SERVICE_TENANT_NAME%,service,g /etc/nova/api-paste.ini
sed -i s,%SERVICE_USER%,nova,g /etc/nova/api-paste.ini
sed -i s,%SERVICE_PASSWORD%,$nova_password,g /etc/nova/api-paste.ini

echo "SETUP NOVA SERVICE FOR KEYSTONE ########"
nova_id=`keystone $keystone_creds service-create --name=nova --type=compute --description="Nova Compute Service" |grep -w id |awk '{print $4}'`
echo "SETUP NOVA ENDPOINT ########"
keystone $keystone_creds endpoint-create --service-id=$nova_id --publicurl=http://$ip:8774/v2/%\(tenant_id\)s --internalurl=http://$ip:8774/v2/%\(tenant_id\)s --adminurl=http://$ip:8774/v2/%\(tenant_id\)s
echo "[DEFAULT]
my_ip=$ip
auth_strategy = keystone
rpc_backend = rabbit
rabbit_host = $ip
rabbit_password = $rabbitmq_password
#VNC
vncserver_proxyclient_address=127.0.0.1
vncserver_listen=0.0.0.0
[database]
connection = mysql://nova:$nova_password@$ip/nova
[keystone_authtoken]
auth_uri = http://$ip:5000
auth_host = $ip
auth_port = 35357
auth_protocol = http
admin_tenant_name = service
admin_user = nova
admin_password = $nova_password" >> /etc/nova/nova.conf
echo "MIGRATE NOVA DB ########"
nova-manage db sync
echo "RESTART NOVA SERVICES... ########"
service nova-api restart; service nova-cert restart; service nova-consoleauth restart; service nova-scheduler restart; service nova-conductor restart; service nova-novncproxy restart
echo "WAITING FOR THE NOVA SERVICES TO RESTART... ########"
sleep 3
nova --os-username=admin --os-password=$admin_pass --os-tenant-name=admin --os-auth-url=http://$ip:35357/v2.0 image-list

echo -e "NOVA CONFIGURATION DONE! ########\n"

echo -e "\e[1;32mCINDER INSTALL \e[0m########"
sleep 2
apt-get -y install cinder-api cinder-scheduler
echo "[database]
connection = mysql://cinder:$cinder_password@$ip/cinder
[keystone_authtoken]
auth_uri = http://$ip:5000
auth_host = $ip
auth_port = 35357
auth_protocol = http
admin_tenant_name = service
admin_user = cinder
admin_password = $cinder_password
[DEFAULT]
rpc_backend = rabbit
rabbit_host = $ip
rabbit_port = 5672
rabbit_userid = guest
rabbit_password = $rabbitmq_password" >> /etc/cinder/cinder.conf
echo "CINDER DB_SYNC ########"
cinder-manage db sync
echo "CREATE CINDER USER IN KEYSTONE ########"
keystone $keystone_creds user-create --name=cinder --pass=$cinder_password --email=cinder@example.com
echo "ADD ROLE ADMIN TO CINDER USER ########"
keystone $keystone_creds user-role-add --user=cinder --tenant=service --role=admin

echo "SETUP CINDER SERVICE API V1 FOR KEYSTONE ########"
cinder_id=`keystone $keystone_creds service-create --name=cinder --type=volume --description="Cinder Volume Service" |grep -w id |awk '{print $4}'`
echo "SETUP CINDER API V1 ENDPOINT ########"
keystone $keystone_creds endpoint-create --service-id=$cinder_id --publicurl=http://$ip:8776/v1/%\(tenant_id\)s --internalurl=http://$ip:8776/v1/%\(tenant_id\)s --adminurl=http://$ip:8776/v1/%\(tenant_id\)s
echo "SETUP CINDER SERVICE API V2 FOR KEYSTONE ########"
cinder_id2=`keystone $keystone_creds service-create --name=cinder --type=volume2 --description="Cinder Volume Service V2" |grep -w id |awk '{print $4}'`
echo "SETUP CINDER API V2 ENDPOINT ########"
keystone $keystone_creds endpoint-create --service-id=$cinder_id2 --publicurl=http://$ip:8776/v2/%\(tenant_id\)s --internalurl=http://$ip:8776/v2/%\(tenant_id\)s --adminurl=http://$ip:8776/v2/%\(tenant_id\)s
echo "RESTART CINDER-API AND REGISTRY SERVICES... ########"
service cinder-scheduler restart
service cinder-api restart

echo -e "CINDER CONFIGURATION DONE! ########\n"

echo -e "\e[1;32mTROVE INSTALL \e[0m########"
sleep 2
apt-get install -y python-trove python-troveclient python-glanceclient trove-common trove-api trove-taskmanager
echo "CREATE TROVE USER IN KEYSTONE ########"
keystone $keystone_creds user-create --name=trove --pass=$trove_passowrd --email=trove@example.com
echo "ADD ROLE ADMIN TO TROVE USER ########"
keystone $keystone_creds user-role-add --user=trove --tenant=service --role=admin
echo "SETUP TROVE SERVICE API FOR KEYSTONE ########"
trove_id=`keystone $keystone_creds service-create --name=trove --type=database --description="OpenStack Database Service" |grep -w id |awk '{print $4}'`
echo "SETUP TROVE API ENDPOINT ########"
keystone $keystone_creds endpoint-create --service-id=$trove_id --publicurl=http://$ip:8779/v1.0/%\(tenant_id\)s --internalurl=http://$ip:8779/v1.0/%\(tenant_id\)s --adminurl=http://$ip:8779/v1.0/%\(tenant_id\)s

trove_conf=( /etc/trove/trove.conf /etc/trove/trove-taskmanager.conf /etc/trove/trove-conductor.conf )

for i in "${trove_conf[@]}"
do
cat >> $i << EOL
[DEFAULT]
log_dir = /var/log/trove
trove_auth_url = http://$ip:5000/v2.0
nova_compute_url = http://$ip:8774/v2
cinder_url = http://$ip:8776/v1
swift_url = http://$ip:8080/v1/AUTH_
sql_connection = mysql://trove:$trove_password@$ip/trove
notifier_queue_hostname = $ip
rabbit_password = $rabbitmq_password
default_datastore = mysql
add_addresses = True
network_label_regex = ^NETWORK_LABEL$
nova_proxy_admin_user = admin
nova_proxy_admin_pass = $nova_password
nova_proxy_admin_tenant_name = service
EOL
done

cat >> /etc/trove/api-paste.ini << EOL
[filter:authtoken]
auth_host = $ip
auth_port = 35357
auth_protocol = http
admin_user = trove
admin_password = $nova_password
admin_token = $token
admin_tenant_name = service
signing_dir = /var/cache/trove
EOL

echo "DB SYNC"
trove-manage db_sync
trove-manage datastore_update mysql ''

cat >> /etc/trove/trove-guestmanager.conf << EOL
rabbit_host = $ip
rabbit_password = $rabbitmq_password
nova_proxy_admin_user = admin
nova_proxy_admin_pass = $nova_password
nova_proxy_admin_tenant_name = service
trove_auth_url = http://$ip:35357/v2.0
EOL

echo "RESTART TROVE: API/TASKMANAGER/CONDUCTOR SERVICES... ########"
service trove-api restart
service trove-taskmanager restart
service trove-conductor restart

echo -e "TROVE CONFIGURATION DONE! ########\n"

echo -e "\e[1;32mDASHBOARD INSTALL \e[0m########"

echo "SETUP HORIZON WITH NGINX + SSL"
apt-get install -y build-essential python-dev python-pip nginx-extras memcached node-less uwsgi uwsgi-plugin-python openstack-dashboard
apt-get -y remove --purge openstack-dashboard-ubuntu-theme
pip install uwsgi

cat > /etc/nginx/sites-enabled/default << EOL
server {
  listen 443;
  server_name _;

  ssl on;
  ssl_certificate /etc/nginx/ssl/server.crt;
  ssl_certificate_key /etc/nginx/ssl/server.key;

  location / { try_files \$uri @horizon; }
    location @horizon {
    include uwsgi_params;
    uwsgi_pass unix:/tmp/horizon.sock;
  }

  location /static {
    alias /usr/share/openstack-dashboard/static;
  }
}
EOL

mkdir /etc/nginx/ssl/ && cd /etc/nginx/ssl
openssl genrsa -out server.key 1024
openssl req -new -newkey rsa:1024 -key server.key -out server.csr -subj "/C=US/ST=CA/L=San Francisco/O=Me Corp./CN=server"
openssl x509 -req -days 365 -in server.csr -signkey server.key -out server.crt

cat > /etc/uwsgi/horizon.ini << EOL
[uwsgi]
master = true
processes = 2
threads = 2
chmod-socket = 666

socket = /tmp/horizon.sock
pidfile = /tmp/horizon.pid
log-syslog = '[horizon]'

chdir = /usr/share/openstack-dashboard/
env = DJANGO_SETTINGS_MODULE=openstack_dashboard.settings
module = django.core.handlers.wsgi:WSGIHandler()
EOL

cat > /etc/init/horizon.conf << EOL
description "OpenStack Horizon App"

start on runlevel [2345]
stop on runlevel [!2345]

respawn

exec uwsgi --ini /etc/uwsgi/horizon.ini
EOL

sed -i "s/\/horizon\/auth\/login\//\/auth\/login\//g" /etc/openstack-dashboard/local_settings.py
sed -i "s/\/horizon\/auth\/logout\//\/auth\/login\//g" /etc/openstack-dashboard/local_settings.py
sed -i "s/\/horizon/\//g" /etc/openstack-dashboard/local_settings.py
sed -i "s/OPENSTACK_HOST = \"127.0.0.1\"/OPENSTACK_HOST = \"$ip\"/g" /etc/openstack-dashboard/local_settings.py
service nginx restart
service horizon start

echo -e "\n\e[1;32mDone! \e[0m########\n"
echo -e "You can access Horizon here: \e[1mhttps://$ip\e[0m"
echo -e "User: \e[1madmin\e[0m / Password: \e[1m$admin_pass\e[0m"
echo -e "This script took \e[4m$SECONDS seconds\e[0m to finish!"
