## This document includes code snippets to set up various parts of the DC/OS Spark environment

# Set up hdfs (based on dc/os hdfs package), and configure command line access to hdfs from a node in your cluster
(Parts of this can be done with the mesosphere Docker images, but this allows other command line tools to be able to access it as well)

Install one of the hdfs packages from the Mesosphere universe (https://docs.mesosphere.com/service-docs/ or https://docs.mesosphere.com/service-docs/beta-hdfs/)

Configure it as necessary.

Then, from within your cluster, you can access hdfs from the command line by:
1. Downloading the Hadoop binary package
2. Download `core-site.xml` and `hdfs-site.xml` from your hdfs service
3. Set up your path and environment variables so we have access to the hdfs binaries, libraries, and configuration.  Also, install and configure Java if it's not already configured

Download and configure the Hadoop binary package:
```
# Switch to root
sudo su -

# Download the hadoop binary package
curl -LO http://mirror.reverse.net/pub/apache/hadoop/common/hadoop-2.6.5/hadoop-2.6.5.tar.gz

# Extract it and put it in /opt/hadoop
tar -xzvf hadoop-2.6.5.tar.gz
mv hadoop-2.6.5 /opt/hadoop
```

Download `core-site.xml` and `hdfs-site.xml` from your hdfs service 

```
# Download core-site.xml and hdfs-site.xml to /opt/hadoop/etc/hadoop (and back up the existing instances)
cd /opt/hadoop/etc/hadoop/
mv hdfs-site.xml hdfs-site.xml.bak-$(date +%Y%m%d-%H%M%S)
mv core-site.xml core-site.xml.bak-$(date +%Y%m%d-%H%M%S)
curl -O api.hdfs.marathon.l4lb.thisdcos.directory:80/v1/endpoints/core-site.xml
curl -O api.hdfs.marathon.l4lb.thisdcos.directory:80/v1/endpoints/hdfs-site.xml
```

Set up your path and environment variables so we have access to the hdfs binaries, libraries, and configuration.  Also, install and configure Java if it's not already configured
```
# Install java if t's not already installed
yum install -y java-1.8.0-openjdk
# Set JAVA_HOME
echo "JAVA_HOME=/usr/lib/jvm/jre" >> ~/.bash_profile
echo "export JAVA_HOME" >> ~/.bash_profile


# Add /opt/hadoop/bin to your PATH, and set HADOOP_HOME
echo 'HADOOP_HOME=/opt/hadoop' >> ~/.bash_profile
echo "export HADOOP_HOME" >> ~/.bash_profile
echo 'PATH=$PATH:/opt/hadoop/bin' >> ~/.bash_profile
sed -i '/export PATH/d' ~/.bash_profile 
echo "export PATH" >> ~/.bash_profile
```

Verify
```
hdfs dfs -ls /
```