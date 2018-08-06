# Commands to prepare Centos 7.5 for DC/OS.
# Used for learning, not for anything production-ready.

# SELinux
sudo sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
sudo setenforce permissive

# Overlay
sudo tee /etc/modules-load.d/overlay.conf <<-'EOF'
overlay
EOF
sudo modprobe overlay

# Net-tools
sudo yum makecache fast
sudo yum install -y net-tools ipset unzip yum-utils

# Docker
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo yum install -y docker-ce-17.06.0.ce

sudo systemctl start docker
sudo systemctl enable docker

# Nogroup
sudo groupadd nogroup


#######
sudo mkdir -p /var/lib/mesos
sudo mkfs.xfs -n ftype=1 /dev/xvdf
echo "UUID=$(sudo blkid -o value /dev/xvdf | head -1)    /var/lib/mesos   xfs defaults     0 0" | sudo tee -a /etc/fstab
sudo mount -a