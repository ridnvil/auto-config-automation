#!/bin/bash
#flags
while test $# -gt 0; do
           case "$1" in
                -user)
                    shift
                    gitusers=$1
                    shift
                    ;;
                -pass)
                    shift
                    gitpasswd=$1
                    shift
                    ;;
		-khost)
                    shift
                    kafkahost=$1
                    shift
                    ;;
                *)
                   echo "$1 error"
                   return 1;
                   ;;
          esac
  done

if [ -z "$gitusers" ] || [ -z "$gitpasswd" || [ -z "$kafkahosts"  ]; then
    echo "usage: run.sh -user usergit -pass passwordgit -khost kafkahost" 1>&2
    exit 1
fi

#dependency checker
if ! command -v wget &> /dev/null
	then
	sudo yum -y install wget curl
	else
	echo "wget installed"
fi

#OpenJDK
echo "Install OpenJDK 14....."
if ! command -v java &> /dev/null
	then
	cd /tmp && wget https://download.java.net/java/GA/jdk14/076bab302c7b4508975440c56f6cc26a/36/GPL/openjdk-14_linux-x64_bin.tar.gz && tar xvf /tmp/openjdk-14_linux-x64_bin.tar.gz
	sudo mv /tmp/jdk-14 /opt/
	else
	echo "Java installed. Skip!"
fi

if [ -d "/opt/jdk-14" ]; then
	echo "OpenJDK 14 Installed to /opt/jdk-14"
	else
	echo "error" && exit 1
fi

echo "Configure Java environment"
sudo tee /etc/profile.d/jdk14.sh <<EOF > /dev/null
export JAVA_HOME=/opt/jdk-14
export PATH=\$PATH:\$JAVA_HOME/bin
EOF

chmod +x /etc/profile.d/jdk14.sh
echo "source /etc/profile.d/jdk14.sh" >> ~/.bashrc
source /etc/profile.d/jdk14.sh && java -version
echo "Done. OpenJDK 14 Installed"

#Install NodeJS
if ! command -v node &> /dev/null
	then
	sudo yum install -y gcc-c++ make
	curl -sL https://rpm.nodesource.com/setup_12.x | sudo -E bash -
	sudo yum install nodejs -y
	else
	echo "NodeJS installed. Skip!"
fi

#Install Appium
echo "Installing Appium & Appium Doctor..."
if ! command -v appium &> /dev/null
	then
	npm install -g appium --unsafe-perm=true --allow-root
	else
	echo "Appium installed. Skip!"
fi

#kill installer if appium not installed
if ! command -v appium &> /dev/null
	then
	echo "error. appium not installed"
	exit 1
	else
	echo "Appium installed. Go!"
fi

#Try Install Appium Doctor
if ! command -v appium-doctor &> /dev/null
	then
	npm install -g appium-doctor
	else
	echo "Appium installed. Skip!"
fi

#kill installer if appium-doctor not installed
if ! command -v appium-doctor &> /dev/null
	then
	echo "error. appium-doctor not installed"
	exit 1
	else
	echo "Appium Doctor installed. Go!"
fi

#Install AndroidSDK
echo "Installing AndroidSDK..."
sudo yum install unzip -y
if [ ! -d "/root/Android/platform-tools" ]; then
	mkdir ~/Android
	cd /tmp && wget https://www.dropbox.com/s/aah1dutom9rwfzy/android-tools.zip?dl=1 -O android-tools.zip && unzip /tmp/android-tools.zip -d ~/Android
	else
	echo "Android SDK Installed. Skip..."
fi

echo "Configure Android Environment"

sudo tee  /etc/profile.d/androidsdk.sh <<EOF >/dev/null
export ANDROID_HOME=/root/Android
export PATH=\$PATH:\$ANDROID_HOME/tools
export PATH=\$PATH:\$ANDROID_HOME/platform-tools
EOF

chmod +x /etc/profile.d/androidsdk.sh
echo "source /etc/profile.d/androidsdk.sh" >> ~/.bashrc
source /etc/profile.d/androidsdk.sh && adb --version

#Create Appium Daemon
echo "Create Appium Daemon"
mkdir ~/Android/bashscripts/

sudo tee  ~/Android/bashscripts/appium-exec.sh <<EOF >/dev/null
#!/usr/bin/env bash
export ANDROID_HOME=/root/Android
export PATH=\$PATH:\$ANDROID_HOME/tools
export PATH=\$PATH:\$ANDROID_HOME/platform-tools
export JAVA_HOME=/opt/jdk-14
kill \$(lsof -t -i:4723)
/usr/bin/appium
EOF

chmod +x ~/Android/bashscripts/appium-exec.sh

sudo tee  /etc/systemd/system/appiumd.service <<EOF >/dev/null
[Unit]
Description=Appium Systemd
After=network.target
[Service]
Type=simple
Restart=always
RestartSec=1
ExecStart=/root/Android/bashscripts/appium-exec.sh
[Install]
WantedBy=multi-user.target
EOF

#Install Maven
echo "Install Java Maven"
wget https://downloads.apache.org/maven/maven-3/3.6.3/binaries/apache-maven-3.6.3-bin.zip -P /tmp
sudo unzip /tmp/apache-maven-3.6.3-bin.zip -d /opt
sudo ln -s /opt/apache-maven-3.6.3 /opt/maven

echo "Configure Java Maven"
sudo tee /etc/profile.d/maven.sh <<EOF > /dev/null
export JAVA_HOME=/opt/jdk-14
export M2_HOME=/opt/maven
export MAVEN_HOME=/opt/maven
export PATH=\${M2_HOME}/bin:\${PATH}
EOF

sudo chmod +x /etc/profile.d/maven.sh
echo "source /etc/profile.d/maven.sh" >> ~/.bashrc
source /etc/profile.d/maven.sh && mvn --version

#Auto Deploy
echo "Project deploy.."
if [ -d "/root/Automation" ]; then
	echo "Directory Exist."
	else
	mkdir ~/Automation
fi

cd ~/Automation
git clone https://$gitusers:$gitpasswd@git.this.my.id/automation_tools/automation_services/device_monitoring.git
git clone https://$gitusers:$gitpasswd@git.this.my.id/automation_tools/automation_services/automation_services_database.git
git clone https://$gitusers:$gitpasswd@git.this.my.id/automation_tools/automation_services/automation_services_producer.git
git clone https://$gitusers:$gitpasswd@git.this.my.id/automation_tools/automation_services/automation_services_consumer.git

#Create Docker Compose
echo "generating docker compose..."
mkdir /root/Automation/automation_tools
tee  /root/Automation/automation_tools/docker-compose.yaml <<EOF >/dev/null
version: '2'

services:
  zookeeper:
    image: 'bitnami/zookeeper:latest'
    ports:
      - '2181:2181'
    environment:
    - ALLOW_ANONYMOUS_LOGIN=yes
    restart: 'always'
  kafka:
    image: 'bitnami/kafka:latest'
    ports:
      - '9092:9092'
    environment:
      - KAFKA_CFG_ZOOKEEPER_CONNECT=automation_tools_zookeeper
      - ALLOW_PLAINTEXT_LISTENER=yes
      - KAFKA_CFG_LISTENERS=PLAINTEXT://:9092
      - KAFKA_CFG_ADVERTISED_LISTENERS=PLAINTEXT://$kafkahosts:9092
    restart: 'always'
  mariadb:
    image: 'mariadb:latest'
    ports:
      - '6009:3306'
    environment:
      - MYSQL_ROOT_PASSWORD=M1r34cl3@
    restart: 'always'
  redis:
    image: 'redis:latest'
    ports:
      - '6379:6379'
    restart: 'always'
EOF

#Allow Port
sudo firewall-cmd --zone=public --permanent --add-port=4723/tcp
sudo firewall-cmd --zone=public --permanent --add-port=8081/tcp
sudo firewall-cmd --zone=public --permanent --add-port=9092/tcp
sudo systemctl daemon-reload && sudo systemctl enable appiumd && sudo systemctl start appiumd
