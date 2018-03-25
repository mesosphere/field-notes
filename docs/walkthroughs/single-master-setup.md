# Overview
This document provides a quick walkthrough of using the DC/OS community edition advanced installer to stand up a basic DC/OS cluster on a set of CentOS 7.3 boxes (built using the 1611 minimal ISO).

This document isn't meant to be used to build a production-ready stack (it's missing a lot of the security configurations, etc.).  Rather, this is a quick-start guide to stand up a basic DC/OS cluster with distributed masters; it's meant to familiarize new users with the installation method in general, using a common environment.

---

*I prefer the advanced installation method.  In my opinion, it's much easier to set up, use, and troubleshoot.*

---

Requirements: 4 systems, all configured as follows:
* CentOS 7.3 (CentOS-7-x86_64-Minimal-1611.iso)
* Static IP addresses
* SSH access, with sudo permissions (using linux user 'admin' with sudo access)

## Architecture:
This walkthrough details the deployment of a 3-master cluster, with one public agent and one private agent.  For the purposes of this walkthrough, these are the IP addresses used:

Bootstrap node:
* 172.16.125.20

Master nodes:
* 172.16.125.21

Public Agent node:
* 172.16.125.25

Private Agent node:
* 172.16.125.26

---

*Hint: DC/OS requires an odd number of masters.*

---

# Prerequisites Installation / Configuration

This section details the system configurations that should be made and/or verified before installing DC/OS.

## Time synchronization (all nodes)

All DC/OS nodes must be synchronized via a standard time synchronization mechanism.  centos7.3 comes with `chrony` configured out of the box.  `ntpd` will also work.  You can verify chrony sync state with the `chronyc tracking` command:

```bash
chronyc tracking
Reference ID    : 45.33.84.208 (christensenplace.us)
Stratum         : 3
Ref time (UTC)  : Fri Jun 16 17:14:31 2017
System time     : 0.000268338 seconds slow of NTP time
Last offset     : -0.000494987 seconds
RMS offset      : 0.125952706 seconds
Frequency       : 8.250 ppm slow
Residual freq   : -0.038 ppm
Skew            : 1.565 ppm
Root delay      : 0.024103 seconds
Root dispersion : 0.002404 seconds
Update interval : 516.8 seconds
Leap status     : Normal
```

## Disable the firewall (all nodes)

Disable the firewall on all nodes:

```bash
sudo systemctl stop firewalld
sudo systemctl disable firewalld
```


## Enable the overlay kernel module (all nodes)

DC/OS requires the use of the overlay linux kernel module.  It can be enabled by running this command, which will create the overlay configuration file at /etc/modules-load.d/overlay.conf:

```
sudo tee /etc/modules-load.d/overlay.conf <<-'EOF'
overlay
EOF
```

This will not take effect until the system is rebooted.  The next step (disable SELinux) includes a reboot.

## Set SELinux to 'permissive' mode (all nodes)

As of version 1.9.0, DC/OS currently does not support SELinux.  SELinux must be set to permissive mode (or disabled) in order to install and run DC/OS.

This is a two step process:
- Change the /etc/selinux/config file SELINUX mode to 'permissive'
- Reboot the system

You can change the config file with this sed command:

```bash
sudo sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
```

Then, reboot the system:
```
sudo init 6
```

---

*Once the systems have finished rebooting, you can verify that the above two steps were successful by running `getenforce` and `lsmod | grep overlay`*

---


## Install Docker (all nodes)

While Docker images can be run on DC/OS using the Universal Container Runtime (UCR), as of 1.9.0 the Docker engine is still a prerequisite for the installation process to complete.  This is because we actually use Docker containers to deploy some of the packages.

This is a three step process:
- Configure CentOS with the Docker yum repo
- Configure Docker to use OverlayFS (basically, we're configuring a systemd override file before Docker is first installed and started
- Install and start the Docker engine

1. Set up the Docker yum repo:

```bash
sudo tee /etc/yum.repos.d/docker.repo <<-'EOF'
[dockerrepo]
name=Docker Repository
baseurl=https://yum.dockerproject.org/repo/main/centos/7/
enabled=1
gpgcheck=1
gpgkey=https://yum.dockerproject.org/gpg
EOF
```

2. Configure Docker to use OverlayFS (we're creating a systemd override configuration file in a docker.service.d directory)

```bash
sudo mkdir -p /etc/systemd/system/docker.service.d

sudo tee /etc/systemd/system/docker.service.d/override.conf <<- 'EOF'
[Service]
Restart=always
StartLimitInterval=0
RestartSec=15
ExecStartPre=-/sbin/ip link del docker0
ExecStart=
ExecStart=/usr/bin/dockerd --graph=/var/lib/docker --storage-driver=overlay
EOF
```

3. Install Docker engine (1.13.1), using yum, then enable the systemd unit and start it.

```bash
sudo yum install -y docker-engine-1.13.1

sudo systemctl enable docker
sudo systemctl start docker
```


---

*Once the systems have finished rebooting, you can verify docker is running with overlay by running `sudo docker info | grep Storage`*

---

## Other requirements (all nodes)

DC/OS also has a couple other small requirements: you must install `ipset` and `unzip` and you must add the linux group `nogroup`.

Install `unzip` and `ipset`:

```bash
sudo yum install -y unzip ipset
```

Create the group `nogroup`:

```bash
sudo groupadd nogroup
```

# Install DC/OS

Now that all of the requirements are set up, the basic installation process for DC/OS is as follows:

Set up the bootstrap node
- Create a workspace directory on your bootstrap node
- Download the installer to your bootstrap node
- Create the `genconf` directory in your workspace
- Populate your `genconf/ip-detect` file
- Populate your `genconf/config.yaml` file
- Generate the configuration generation script
- Host the `genconf/serve` directory via nginx

On each master:
- Create workspace directory
- Download the `dcos_install.sh` script from the bootstrap node
- Run the `dcos_install.sh` script with the `master` option

On each Agent:
- Create workspace directory
- Download the `dcos_install.sh` script from the bootstrap node
- Run the `dcos_install.sh` script with the `slave` option

On each Public Agent:
- Create workspace directory
- Download the `dcos_install.sh` script from the bootstrap node
- Run the `dcos_install.sh` script with the `slave_public` option

---

*DC/OS uses the `pkgpanda` package manager, instead of yum or apt or some other package management tool, in order to be fully cross-platform compliant.  The above process basically turns your bootstrap node into a pkgpanda repository (hosted over http on nginx)*

*The installation script is then downloaded to each node, and run from each node.  The installation script essentially runs a bunch of pkgpanda download and installs to install of the DC/OS components*

---

## Set up the bootstrap node:

#### Create the workspace directory
Create a workspace directory on your bootstrap node, and cd to it (I'm using 190 to refer to DC/OS version 1.9.0; you can use whatever directory you want):

```bash
mkdir 190
cd 190
```

#### Download the bootstrap script (dcos_generate-config.sh) to the workspace
In the dcos_190 directory, download the bootstrap script (or use some mechanism such as scp to get it over to the bootstrap node and put it in dcos_190):

```bash
curl -LO https://downloads.dcos.io/dcos/stable/commit/0ce03387884523f02624d3fb56c7fbe2e06e181b/dcos_generate_config.sh
```

#### Create the genconf directory (with your workspace directory)
Create the genconf directory within the 190 directory 

```bash
mkdir genconf
```

#### Create the genconf/ip-detect file

Use vi to create a genconf/ip-detect file.  This is used to self-identify the IP address that will be used for internal communication between nodes.  When run, it should output an IP address that is reachable from all nodes within the cluster (this is also used as the 'hostname' for the DC/OS UI.  Examples of ip-detect files for different environments are available here: https://dcos.io/docs/1.8/administration/installing/custom/advanced/

For the purposes of this document, I'm using a very simple ip-detect file that, when run, outputs the first ip address.  This may or may not be suitable for your environment (for example, in some environments, depending on the shell, this will return a different IP address, which will cause issues).

This script is copied to each node in your cluster, so it should work on all cluster nodes.

> vi genconf/ip-detect

```
#!/bin/sh
hostname -I | awk '{print $1}'
```

Use vi to create a genconf/config.yaml.  Make sure that the bootstrap URL matches the output of ip-detect when run from the bootstrap node, and make sure the master IPs match the outputs of ip-detect run on your mater nodes.

#### Create the genconf/config.yaml file
Create a yaml file that contains all the configurations used to build DC/OS.  Make sure to update the `bootstrap_url` with the IP address of your bootstrap node (whatever is returned via ip-detect) and `master_list` with the IP addresses of your master nodes (again, output of ip-detect).

*You must have an odd number of masters.*

> vi genconf/config.yaml

```yml
---
bootstrap_url: http://172.16.125.20
cluster_name: 'dcos-oss'
exhibitor_storage_backend: static
master_discovery: static
oauth_enabled: 'false'
master_list:
 - 172.16.125.21
resolvers:
- 8.8.4.4
```

---

*This is the bare minimum config.yaml.  Additional configuration options are documented here: https://dcos.io/docs/1.8/administration/installing/custom/configuration-parameters/*

---

An annotated version of the config.yaml can be found on a separate page [here](config.yaml.md).


This should be your directory structure now:
- <190>/dcos_generate_config.sh
- <190>/genconf/ip-detect
- <190>/genconf/config.yaml

```
[admin@localhost 190]$ ls -alh *
-rw-rw-r--. 1 admin admin 829830566 Jun 16 14:38 dcos_generate_config.sh

genconf:
total 8
-rw-rw-r--. 1 admin admin   209 Jun 16 15:38 config.yaml
-rwxrwxr-x. 1 admin admin    50 Jun 16 15:30 ip-detect
```

#### Run the bootstrap script (dcos_generate-config.sh):
Run the dcos_generate_config.sh script (with sudo).  This will generate a bunch of content and put it in `<190>/genconf/serve`.  This will basically serve as your http and pkgpanda repository.

```bash
sudo bash dcos_generate_config.sh
```

You can do an `ls` on this directory to see the contents that are served:

```
[admin@localhost 190]$ ls -alh genconf/serve
total 40K
drwxrwxrwx.  4 root  root   119 Jun 16 15:39 .
drwxrwxr-x.  4 admin admin   97 Jun 16 15:39 ..
drwxrwxrwx.  2 root  root   131 Jun 16 15:39 bootstrap
-rw-rw-rw-.  1 root  root    40 Jun 16 15:39 bootstrap.latest
-rw-rw-rw-.  1 root  root   12K Jun 16 15:39 cluster-package-info.json
-rw-rw-rw-.  1 root  root   19K Jun 16 15:39 dcos_install.sh
drwxrwxrwx. 67 root  root  4.0K Jun 16 15:39 packages
```

#### Start nginx to host the repo and artifacts

Start nginx to actually host the artifacts so that your nodes can download and install from the bootstrap:

```
sudo docker run -d -p 80:80 --name bootstrap-190 -v $PWD/genconf/serve:/usr/share/nginx.html:ro nginx
```

Now, if you curl the bootstrap URL with a path of /cluster-package-info.json, you should get a JSON file that lists all of the packages that make up DC/OS:

```
$ curl http://172.16.125.20/cluster-package-info.json
{
  "3dt":{
    "filename":"packages/3dt/3dt--7847ebb24bf6756c3103902971b34c3f09c3afbd.tar.xz",
    "id":"3dt--7847ebb24bf6756c3103902971b34c3f09c3afbd"
  },
  ...
    "toybox":{
    "filename":"packages/toybox/toybox--f235594ab8ea9a2864ee72abe86723d76f92e848.tar.xz",
    "id":"toybox--f235594ab8ea9a2864ee72abe86723d76f92e848"
  }
}
```

## Install DC/OS on your master nodes.

For each master node, follow this process:

SSH in to the master node

Make a workspace directory

```
mkdir -p /tmp/dcos/190 && cd /tmp/dcos/190
```

Download the installer script from the boostrap node (replace IP with your bootstrap node IP):
```
curl -LO http://172.16.125.20/dcos_install.sh
```

Run the script with the 'master' flag (using sudo):
```
sudo bash dcos_install.sh master
```

If you see any errors here, you've probably missed a prerequisite.

---

*If you have multiple masters, the cluster will not converge (and the UI will not work) until you've run this on all of your masters.*

---

This installation may take several minutes (even after the script has exited).  After the script has exited, you can monitor progress with the following:

Use this command to follow the dcos-setup systemd unit (when it hits 'Started Pkgpanda...' then this step is complete) (ctrl-c to exit):
```
sudo journalctl -f -u dcos-setup
```

Watch cluster convergence at http://<master-ip>:8181:  (will not converge unless the installation process has been completed on all masters)(ctrl-c to exit):

```
sudo journalctl -f -u dcos-exhibitor
```

Watch process convergence with this watch command:  (when all units say `loaded` and `active`, you should be good to go)(ctrl-c to exit):

```
watch 'systemctl list-units dcos-*'
```

## Install DC/OS on each of your private agent nodes.

For each private agent node, follow this process:

SSH in to the master node

Make a workspace directory

```
mkdir -p /tmp/dcos/190 && cd /tmp/dcos/190
```

Download the installer script from the boostrap node (replace IP with your bootstrap node IP):
```
curl -LO http://172.16.125.20/dcos_install.sh
```

Run the script with the 'slave' flag (using sudo):
```
sudo bash dcos_install.sh slave
```

This may take several minutes to complete.  You can do this for all of your agents at the same time (from different shell sessions).


## Install DC/OS on each of your public agent nodes.

For each public agent node, follow this process:

SSH in to the master node

Make a workspace directory

```
mkdir -p /tmp/dcos/190 && cd /tmp/dcos/190
```

Download the installer script from the boostrap node (replace IP with your bootstrap node IP):
```
curl -LO http://172.16.125.20/dcos_install.sh
```

Run the script with the 'slave_public' flag (using sudo):
```
sudo bash dcos_install.sh slave_public
```

This may take several minutes to complete.  You can do this for all of your agents at the same time (from different shell sessions).

# Wait for installation to complete:

It may take several minutes for your cluster to completely install itself.  Each node will run a set of systemd service units that run the various services that comprise DC/OS.

The installation will start with two systemd units (`dcos-download.service` and `dcos-setup.service`) which will download and install everything from your bootstrap node.  Once these have completed, they will install additional systemd units and remove themselves.

To monitor the deployment of your systemd units, you can log into each of your nodes (master and agents), and see the overall status with this command:

```
sudo systemctl list-units | grep dcos
```

Additionally, you can monitor individual systemd units with this:

```
sudo journalctl -fu dcos-<servicename>.service
```

(For example `sudo systemctl -fu dcos-mesos-master.service`)


# Success!

Once all of the systemd units on your masters are fully loaded:active, you should be able to log in to the DC/OS UI.  Navigate to http://master-ip/ and you should get the DC/OS UI.

<!--- # Todo: Add '>' style commands for better markdown output. --->
