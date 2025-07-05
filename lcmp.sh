#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

OS=$(cat /etc/os-release|grep PLATFORM_ID|grep -oE "el7")
if [[ $OS = el7 ]]; then
echo ＂不支持 RHEL,Centos/7＂ && exit 1
fi

OS1=$(cat /etc/os-release|grep PLATFORM_ID|grep -oE "el10")
if [[ $OS1 = el10 ]]; then
echo ＂不支持 RHEL,AlmaLinux,Rocky/10＂ && exit 1
fi

#安装依赖
dnf install wget tar gzip chkconfig -y

#安装caddy
cd /usr/local
wget https://dl.google.com/go/go1.16.15.linux-amd64.tar.gz
tar xzf go1.16.15.linux-amd64.tar.gz
rm -rf go1.16.15.linux-amd64.tar.gz
echo "export PATH=$PATH:/usr/local/go/bin" >> /etc/profile
source /etc/profile
cd
go env -w GO111MODULE=on
CN_CHECK=$(curl -L http://www.qualcomm.cn/cdn-cgi/trace | grep '^loc=' | cut -d= -f2 | grep .)
if [ "${CN_CHECK}" == "CN" ];then
go env -w GOPROXY=https://goproxy.cn,direct
fi
mkdir c
cd c
wget https://raw.githubusercontent.com/lemonsn/shell/refs/heads/main/main.go
wget https://raw.githubusercontent.com/lemonsn/shell/refs/heads/main/go.mod
go mod why
go build
chmod +x caddy
mkdir -p /usr/local/caddy
cp caddy /usr/local/caddy
wget https://raw.githubusercontent.com/lemonsn/shell/refs/heads/main/caddy_centos -O /etc/init.d/caddy
chmod +x /etc/init.d/caddy
chkconfig --add caddy
chkconfig caddy on

#安装mariadb
cd /opt

OS2=$(cat /etc/os-release|grep PLATFORM_ID|grep -oE "el8")
if [[ $OS2 = el8 ]]; then
wget https://dlm.mariadb.com/3782208/MariaDB/mariadb-10.4.34/yum/rhel/mariadb-10.4.34-rhel-8-x86_64-rpms.tar
tar -xf mariadb-10.4.34-rhel-8-x86_64-rpms.tar
mv mariadb-10.4.34-rhel-8-x86_64-rpms mariadb
rm -rf mariadb-10.4.34-rhel-8-x86_64-rpms.tar
fi

OS3=$(cat /etc/os-release|grep PLATFORM_ID|grep -oE "el9")
if [[ $OS3 = el9 ]]; then
wget https://dlm.mariadb.com/4262992/MariaDB/mariadb-10.11.13/yum/rhel/mariadb-10.11.13-rhel-9-x86_64-rpms.tar
tar -xf mariadb-10.11.13-rhel-9-x86_64-rpms.tar
mv mariadb-10.11.13-rhel-9-x86_64-rpms mariadb
rm -rf mariadb-10.11.13-rhel-9-x86_64-rpms.tar
fi
cd mariadb
/opt/mariadb/setup_repository
yum install MariaDB-common MariaDB-server MariaDB-client MariaDB-shared MariaDB-backup -y
lnum=$(sed -n '/\[mariadb\]/=' /etc/my.cnf.d/server.cnf)
sed -i "${lnum}acharacter-set-server = utf8mb4\n\n\[client-mariadb\]\ndefault-character-set = utf8mb4" /etc/my.cnf.d/server.cnf
systemctl enable mariadb
systemctl start mariadb
openssl rand -base64 12 > pw
PW=$(cat pw)
db_pass="$PW"
mysql -e "grant all privileges on *.* to root@'127.0.0.1' identified by \"${db_pass}\" with grant option;"
mysql -e "grant all privileges on *.* to root@'localhost' identified by \"${db_pass}\" with grant option;"
mysql -uroot -p${db_pass} 2>/dev/null <<EOF
drop database if exists test;
delete from mysql.db where user='';
delete from mysql.db where user='PUBLIC';
delete from mysql.user where user='';
delete from mysql.user where user='mysql';
delete from mysql.user where user='PUBLIC';
flush privileges;
exit
EOF
