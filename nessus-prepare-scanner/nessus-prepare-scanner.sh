#############################
########### CentOS
#############################

#update, install packages
yum -y update
yum -y install open-vm-tools dnf-automatic yum-utils wget

#mono installation
update-crypto-policies --set DEFAULT:SHA1
rpmkeys --import "http://keyserver.ubuntu.com/pks/lookup?op=get&search=0x3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF"
curl https://download.mono-project.com/repo/centos8-stable.repo | tee /etc/yum.repos.d/mono-centos8-stable.repo
yum -y install mono-devel
update-crypto-policies --set DEFAULT

#enable automatic updates
sed -i 's/apply_updates = no/apply_updates = yes/' /etc/dnf/automatic.conf
systemctl enable --now dnf-automatic.timer

#download/install the new Nessus package
Base_URL="https://www.tenable.com/downloads/api/v2/pages/nessus"
OS_Version=$(cat /etc/os-release | grep -oE 'VERSION_ID="?[[:digit:]]+' | sed s'/VERSION_ID=//' | sed s'/"//g')
Nessus_Downloads=$(curl -k $Base_URL 2> /dev/null)
New_Nessus_Package=$(echo $Nessus_Downloads | grep -oE "Nessus-latest-el$OS_Version.x86_64.rpm")
Download_URL=$Base_URL"/files/"$New_Nessus_Package
curl --request GET --url $Download_URL --output $New_Nessus_Package
rpm -Uvh $New_Nessus_Package

#add firewall rule
firewall-cmd --permanent --zone=public --add-port=8834/tcp

#install Datto agent
wget -O DattoSetup.sh https://concord.centrastage.net/csm/profile/downloadLinuxAgent/[GUID_REDACTED] && sh DattoSetup.sh
reboot now





#############################
########### Fedora
#############################

#update, install packages
dnf -y update
dnf -y install open-vm-tools dnf-automatic yum-utils wget nmap cronie

#enable automatic updates
sed -i 's/apply_updates = no/apply_updates = yes/' /etc/dnf/automatic.conf
systemctl enable --now dnf-automatic.timer

#enable weekly reboot
systemctl start crond.service
systemctl enable crond.service
echo "* 15 * * 0 root reboot now" >> /etc/crontab

#download/install the new Nessus package
Base_URL="https://www.tenable.com/downloads/api/v2/pages/nessus"
Nessus_Downloads=$(curl -k $Base_URL 2> /dev/null)
New_Nessus_Package=$(echo $Nessus_Downloads | grep -oE "Nessus-latest-fc[[:digit:]]+.x86_64.rpm")
Download_URL=$Base_URL"/files/"$New_Nessus_Package
curl --request GET --url $Download_URL --output $New_Nessus_Package
rpm -Uvh $New_Nessus_Package

#add firewall rule
firewall-cmd --permanent --add-port=8834/tcp

#install Datto agent
wget -O DattoSetup.sh https://concord.centrastage.net/csm/profile/downloadLinuxAgent/[GUID_REDACTED] && sh DattoSetup.sh
reboot now






#############################
########### Rocky
#############################

#update, install packages
dnf -y update
dnf -y install open-vm-tools dnf-automatic yum-utils wget firewalld nmap

#mono installation
update-crypto-policies --set DEFAULT:SHA1
rpmkeys --import "http://keyserver.ubuntu.com/pks/lookup?op=get&search=0x3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF"
curl https://download.mono-project.com/repo/centos8-stable.repo | tee /etc/yum.repos.d/mono-centos8-stable.repo
dnf install -y mono-devel
update-crypto-policies --set DEFAULT

#enable automatic updates
sed -i 's/apply_updates = no/apply_updates = yes/' /etc/dnf/automatic.conf
systemctl enable --now dnf-automatic.timer

#download/install the new Nessus package
Base_URL="https://www.tenable.com/downloads/api/v2/pages/nessus"
OS_Version=$(cat /etc/os-release | grep -oE 'VERSION_ID="?[[:digit:]]+' | sed s'/VERSION_ID=//' | sed s'/"//g')
Nessus_Downloads=$(curl -k $Base_URL 2> /dev/null)
New_Nessus_Package=$(echo $Nessus_Downloads | grep -oE "Nessus-latest-el$OS_Version.x86_64.rpm")
Download_URL=$Base_URL"/files/"$New_Nessus_Package
curl --request GET --url $Download_URL --output $New_Nessus_Package
rpm -Uvh $New_Nessus_Package

#add firewall rule
systemctl enable firewalld
systemctl start firewalld
firewall-cmd --permanent --zone=public --add-port=8834/tcp

#install Datto agent
wget -O DattoSetup.sh https://concord.centrastage.net/csm/profile/downloadLinuxAgent/[GUID_REDACTED] && sh DattoSetup.sh
reboot now`