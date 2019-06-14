#!/bin/bash

## todo: check root or sudo permissions to run

NODE_VERSION=v8.11.4
NPM_VERSION=6.4.1
MONGO_URL=mongodb://localhost:27017/rocketchat?replicaSet=rs01 
MONGO_OPLOG_URL=mongodb://localhost:27017/local?replicaSet=rs01
ROOT_URL=http://localhost:3000/
PORT=3000
WEBSERVER=traefik

ROCKETCHAT_DOWNLOAD_URL="https://releases.rocket.chat/latest/download"
NODE_DEB_DOWNLOAD_URL="https://deb.nodesource.com/setup_8.x"
NODE_RPM_DOWNLOAD_URL=https://rpm.nodesource.com/setup_8.x
ROCKETCHAT_DIR=/opt/Rocket.Chat

yellow=`tput setaf 3`;
green=`tput setaf 2`;
clear=`tput sgr0`;

command_exists() {
	command -v "$@" > /dev/null 2>&1
}

node_installed() {
    if command_exists node; then
	    echo true
	else echo false
	fi
}

warn_node_version(){
	node_version=$(node --version 2>/dev/null)
	[ $node_version != $NODE_VERSION ] && echo true || echo false
}

mongo_installed(){
    if command_exists mongo; then
	    echo true
    else echo false
	fi
}

mongo_connect(){
    mongo_running=$(pgrep mongod)
	[ -z $mongo_running ] && echo false && return
    auth_enabled=$(mongo --eval "printjson(db.getUsers())" | grep "Error: command usersInfo requires authentication")
    [ $? == 1 ] && echo false || echo true
}

mongo_storage_mmap(){
    storage=$(mongo --eval "printjson(db.serverStatus().storageEngine)" |grep name |awk -F: '{print $2}'|tr -d , |tr -d \")
	[ $storage == mmapv1 ] && echo true || echo false
}

rocketchat_version(){
	apt-get install -y curl
    rocket_version=$(curl http://localhost:3000/api/info 2>/dev/null |cut -d\" -f4)
	echo $rocket_version
}

get_os_distro(){
	lsb_dist=""
	if [ -r /etc/os-release ]; then
		lsb_dist="$(. /etc/os-release && echo "$ID")"
	fi
	echo "$lsb_dist"
}

apt_configure_mongo(){
	# todo: use variables for urls
    if [ $lsb_dist == "ubuntu" ]; then
        apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 9DA31620334BD75D9DCB49F368818C72E52529D4
        echo "deb [ arch=amd64 ] https://repo.mongodb.org/apt/ubuntu bionic/mongodb-org/4.0 multiverse" \
	    | tee /etc/apt/sources.list.d/mongodb-org-4.0.list
	elif [ $lsb_dist == "debian" ]; then
	    apt-get install -y dirmngr
		apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 9DA31620334BD75D9DCB49F368818C72E52529D4
		echo "deb http://repo.mongodb.org/apt/debian stretch/mongodb-org/4.0 main" \
		| tee /etc/apt/sources.list.d/mongodb-org-4.0.list
	fi
}

yum_configure_mongo(){
	# todo: use variables for urls
    cat << EOF | sudo tee -a /etc/yum.repos.d/mongodb-org-4.0.repo
[mongodb-org-4.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/7/mongodb-org/4.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-4.0.asc
EOF
}

rocketchat_dir_exists(){
	[ -d $ROCKETCHAT_DIR ] && echo true || echo false
}

user_rocketchat_exists(){
    get_rocket_user=$(id -un rocketchat 2>/dev/null)
    [ $get_rocket_user != rocketchat ] && echo true || echo false
}

rocketchat_systemd_file(){
    cat << EOF | tee -a /lib/systemd/system/rocketchat.service
[Unit]
Description=The Rocket.Chat server
After=network.target remote-fs.target nss-lookup.target nginx.target mongod.service
[Service]
ExecStart=/usr/local/bin/node /opt/Rocket.Chat/main.js
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=rocketchat
User=rocketchat
Environment=MONGO_URL=mongodb://localhost:27017/rocketchat?replicaSet=rs01 
Environment=MONGO_OPLOG_URL=mongodb://localhost:27017/local?replicaSet=rs01
Environment=ROOT_URL=
Environment=PORT=
[Install]
WantedBy=multi-user.target
EOF
	sed -i "s/^Environment=ROOT_URL=/Environment=ROOT_URL=$ROOT_URL/" /lib/systemd/system/rocketchat.service
    sed -i "s/^Environment=PORT=/Environment=PORT=$PORT/" /lib/systemd/system/rocketchat.service
}

mongo_systemd_file(){
    cat << EOF | tee -a /etc/systemd/system/mongod.service.d/mongod.conf
[Service]
Type=oneshot
RemainAfterExit=yes
EOF
}

do_install()
    case "$lsb_dist" in
    	## todo: fedora)
		ubuntu|debian)
		    ## todo: check stretch/jessy bionic/?
		    apt-get -y update
		    # install mongo
			if $install_mongo; then
			    $(apt_configure_mongo) # spawn other process
				apt-get update && apt-get install -y mongodb-org
			fi
			# install node
			if $install_node; then
			    curl -sL $NODE_DEB_DOWNLOAD_URL | bash -
			    apt-get install -y build-essential nodejs graphicsmagick
			    npm install -g npm@6.4.1
                npm install -g inherits node-gyp@4.0.0 n && n 8.11.4
			fi
		centos)
		    ## todo: check 6,7,8
			yum -y check-update
			# install mongo
			if $install_mongo; then
			    `yum_configure_mongo`
				yum install -y mongodb-org
			fi
			# install node
			if $install_node; then
			    curl -sL $NODE_RPM_DOWNLOAD_URL | sudo bash - 
				yum install -y gcc-c++ make nodejs
				yum install -y epel-release && yum install -y GraphicsMagick
				npm install -g npm@6.4.1
                npm install -g inherits node-gyp@4.0.0 n && n 8.11.4

		# install rocketchat
		if $install_rocketchat; then
			curl -L $ROCKETCHAT_DOWNLOAD_URL -o /tmp/rocket.chat.tgz
            tar -xzf /tmp/rocket.chat.tgz -C /tmp
			cd /tmp/bundle/programs/server && npm install
			if ! `rocketchat_dir_exists`; then
			    mv /tmp/bundle $ROCKETCHAT_DIR
			else
			    echo "Aborting installation: $ROCKETCHAT_DIR already exists."
			fi
			if ! `user_rocketchat_exists`; then
			    useradd -M rocketchat && sudo usermod -L rocketchat
			fi
			chown -R rocketchat:rocketchat $ROCKETCHAT_DIR
		    # systemd rocketchat
		    `rocketchat_systemd_file`
			# configure mongo
			if $install_mongo
			    sed -i "s/^#  engine:/  engine: mmapv1/"  /etc/mongod.conf
                sed -i "s/^#replication:/replication:\n  replSetName: rs01/" /etc/mongod.conf 
                sed -i "s/^#replication:/replication:\n  replSetName: rs01/" /etc/mongod.conf 
                sed -i "/^processManagement:/a\  fork: true" /etc/mongod.conf
				mkdir /etc/systemd/system/mongod.service.d/
				`mongo_systemd_file`
                systemctl enable mongod && systemctl start mongod
                mongo --eval "printjson(rs.initiate())"
			# start rocketchat
            systemctl enable rocketchat && systemctl start rocketchat
			# install webserver

}
		
do_setup(){
	## todo: disable questions when configure flag
    # check system before setup: node, mongo, rocketchat
	# get user's values
	install_node=false
	install_mongo=false
	install_rocketchat=false

    # node
    if `node_installed`; then
	    if `warn_node_version`; then
			echo "${yellow}Your current node version is: $node_version. RocketChat uses node $NODE_VERSION,\
			 it will be installed using npm and it will become your default system node version. Do you\
			  want to install node anyway? (y/n)${clear}"
            read -e install_node_answer
			if [ $install_node_answer == y ]; then
			    install_node=true
			else
			    echo "Aborting installation: Different nodejs version already exists in the system."
				exit 1
		    fi
        fi
	else
	    install_node=true
	fi
	# mongo
	if `mongo_installed`; then
	    if `mongo_connect`; then
		    if `mongo_storage_mmap`; then
			    echo "${yellow}It appears you already have mongo installed, this script will skip mongo installation\
				 but can't assure successful RocketChat server installation. Would you like to use your mongo installation\
				 for the RocketChat server database? (y/n)${clear}"
                read -e $install_mongo_answer
			    if [ $install_mongo_answer == n ]; then
			        echo "Aborting installation: mongo already exists in the system"
				    exit 1
		        fi
			else
			    echo "Aborting installation: storage engine from previous mongo installation in your system is not mmapv1"
				exit 1
		    fi
		else
		    echo "Aborting installation: connection failed to previous installed mongo in your system"
			exit 1
		fi
	else
	    install_mongo=true
	fi
    # rocketchat
	echo "${yellow}Enter PORT for your RocketChat server installation [3000]: ${clear}" port
    read -p $port
	## todo: add regex check for port
	PORT=${port:-3000}
	if [ -z $rocketchat_version ];then
	    install_rocketchat=true
	else
	    echo "Aborting installation: RocketChat server already exists in your system listening in port $PORT"
		exit 1
	fi
	echo "${yellow}Enter ROOT_URL for your RocketChat server installation: ${clear}" root_url
    read -p $root_url
	## todo: add regex check for root_url
	ROOT_URL=$root_url
	echo "${yellow}Specify webserver for your RocketChat server installation: (caddy/traefik)${clear}"
    read -e $webserver
	WEBSERVER=$webserver
}
			    

function install(){
    do_setup
	do_install
}

function update(){
	do_update
}

install.sh
download rocketctl
place it in /usr/bin
execute rocketctl install

## use source?
## use set or unset
## unset -f fun1 fun2  