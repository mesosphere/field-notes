## Note: not yet published

Note: This is not officially sanctioned/supported by Mesosphere, but generally speaking it should work.

sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat/jenkins.repo
sudo rpm --import https://pkg.jenkins.io/redhat/jenkins.io.key
yum install -y java-1.8.0-openjdk
systemctl install jenkins

systemctl enable jenkins
systemctl start jenkins

# Listens on port 8080 (make sure to set up firewall)

# Install Mesos plugin through UI

Get libmesos from a dc/os node:
scp  192.168.10.35:/opt/mesosphere/lib/libmesos.so .
move it to /var/lib/jenkins/libmesos.so, chown to jenkins

Go to Manage Jenkins > Configure System
Add cloud > mesos cloud
/var/lib/jenkins/libmesos.so
zk://192.168.10.31:2181,192.168.10.32:2181,192.168.10.33:2181/mesos
framework name: whatever
role: whatever (*)
slave username: root
frramework credentials: none
jenkins url: stuff
advanced
checkopinting on, reg off
no label string?
slave cpus 0.5
max executors per slave: 4
remote fs root: /mnt/mesos/sandbox
mesosphere/jenkins-dind:0.5.0-alpine
advanced

docker image: mesosphere/jenkins-dind:0.5.0-alpine
use docker containerizer
privileged
custom docker command shell: yes
wrapper.sh

export LD_LIBRARY_PATH=/var/lib/jenkins/libmesos-bundle/lib:/var/lib/jenkins/libmesos-bundle/lib/mesos:$LD_LIBRARY_PATH
export MESOS_NATIVE_JAVA_LIBRARY=/var/lib/jenkins/libmesos-bundle/lib/libmesos-1.5.0.so

get libmesos bundle here: https://github.com/mesosphere/dcos-jenkins-service/blob/master/Dockerfile#L13
https://downloads.mesosphere.io/libmesos-bundle/libmesos-bundle-1.11.0.tar.gz

get plugin here: https://github.com/mesosphere/dcos-jenkins-service/blob/master/Dockerfile#L162
https://infinity-artifacts.s3.amazonaws.com/mesos-jenkins/mesos.hpi-${MESOS_PLUG_HASH} "${JENKINS_STAGING}/plugins/mesos.hpi" goes to /var/lib/jenkins/plugins/mesos.hpi

Global Security: TCP port for JNLP agents: random


/etc/alternatives/java \
 -Djava.awt.headless=true \
 -DJENKINS_HOME=/var/lib/jenkins \
 -jar /usr/lib/jenkins/jenkins.war \
 --logfile=/var/log/jenkins/jenkins.log \
 --webroot=/var/cache/jenkins/war \
 --httpPort=8080 \
 --debug=5 \
 --handlerCountMax=100 \
 --handlerCountMaxIdle=20
