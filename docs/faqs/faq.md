---
---

# FAQs

This page is a generic list of how-to's and FAQs for DC/OS.

## Why is Mesos changing my resource_id?
In DC/OS 1.10 and below, the following behaviors occur:
* Persistent volumes are attached to a specific Mesos **agent id**.
* Tasks are attached to a specific **agent id**.
* In order to persist **agent id** across process restarts (including node reboots), the following properties must match, otherwise you'll get a metadata conflict:
  * Apache Mesos attributes
  * Resources allocated to an agent

****
*In DC/OS 1.11 and above (Apache Mesos 1.5 and above), attributes can be changed and resources can be **added** but not **subtracted** and the Mesos agent ID can be preserved.**
****

In certain situations, this can cause undesired behavior.  For example, different kernels may interpret the same amount of memory using slightly different calculations, resulting in non-matching resource counts, resulting in a new Mesos agent, resulting in persistent volumes or tasks being unrecoverable.

The reason for this is that by default, certain resources are auto-detected.  The Mesos agent process operates as follows:

1.  Look at environment variable MESOS_RESOURCES (or startup flag --resources) to determine the resources that have been hardcoded.  In DC/OS, this includes disk and ports but does not include CPUs and memory.  This comes formatted as JSON.
2.  Detect the amount of available CPU and memory
3.  Determine if the CPU and memory matches the previously detected CPU and memory, and if it does not match, throw an error.

You can observe this situation by looking at the journal logs for `dcos-mesos-slave`, using this command: `journalctl -flu dcos-mesos-slave`.

In order to work around this, you can hard-code the amount of CPU and memory into the MESOS_RESOURCES environment variable, so that subsequent kernel changes do not cause conflicts.

On a generic DC/OS node that has no reserved resources (you may have to do some manaul verification here), you caon configure resources to be hardcoded by running this query:

```bash
echo MESOS_RESOURCES=\'$(curl -s $(hostname -i):5051/state.json | jq -c '.unreserved_resources_full' | sed 's/,/, /g; s/:/: /g' )\' >> /var/lib/dcos/mesos-resources
```

What this does: it looks at the full list of unreserved resources on the node (available through the Mesos agent API), and creates an environment variable (used by dcos-mesos-slave) that has the hardcoded settings.  This will prevent the autodetection of resources available.

Alternately, if you have reserved resources in use, you can try something like this:

```bash
curl -s $(hostname -i):5051/state.json > state.json
grep MESOS_RESOURCES /var/lib/dcos/mesos-resources | head -1 | awk -F'=' '{print $2}' | tr "'" " " | jq -c '.[]' > resources.json
jq '. | {mem: .resources.mem, cpus: .resources.cpus}' state.json > cpu_mem.json
jq --slurpfile r cpu_mem.json  -c '.unreserved_resources_full[] | select(.name == "mem") | .scalar.value = $r[0].mem' state.json >> resources.json
jq --slurpfile r cpu_mem.json  -c '.unreserved_resources_full[] | select(.name == "cpus") | .scalar.value = $r[0].cpus' state.json >> resources.json
echo MESOS_RESOURCES=\'$(cat resources.json | jq -c -s .)\' >> /var/lib/dcos/mesos-resources
```

This does something similar, but it looks all resources and merges it with the current setting of resources.  **Definitely test before you use this.**

## How do I cURL (`curl`) an endpoint exposed as a socket?

This isn't really a DC/OS-specific thing, but it's useful in general for endpoints that are not exposed as TCP endpoints.

First, determine what the socket is, and what the endpoint is.  For example, the Mesos master metrics API is exposed as a socket on DC/OS Masters.  This is documented on the 
[Master API Routes page](https://docs.mesosphere.com/1.11/api/master-routes/#system)
and the [Metrics API page](https://docs.mesosphere.com/1.11/metrics/metrics-api/).

In this case, the socket file is `/run/dcos/dcos-metrics-master.sock` and the endpoint is /v0/node.  So you can access this via:

```
curl --unix-socket /run/dcos/dcos-metrics-master.sock http://dummy/v0/ping
```

and work outward from there.  Note that determining the endpoint URIs may need some trial and error (for example, to determine whether the endpoint should include the `/metrics/`, e.g., `http://dummy/metrics/v0/ping` vs. `http://dummy/v/0/ping`


## How do I find the latest version of the DC/OS CLI?

DC/OS CLI releases do not strictly line up with the DC/OS versions - they're released independently.  Because of this, the DC/OS CLI links found in the DC/OS UI may not always be up to date.  You can find the latest versions here:

https://github.com/dcos/dcos-cli/releases

## How come I can't use the `dcos security` command?

The `dcos security` command comes from the dcos-enterprise-cli Universe package, and can be installed by running `dcos package install dcos-enterprise-cli --cli`.  Note that the features of this CLI add-on will only work with the Enterprise edition of DC/OS.

## How do I configure additional Mesos attributes on my nodes, for use with constraints?

The official documentation for this can be found here: https://docs.mesosphere.com/1.9/installing/faq/#q.-how-to-add-mesos-attributes-to-nodes-to-use-marathon-constraints

Alternately, you can do this on a per-node basis by:

1) Editing and/or creating /var/lib/dcos/mesos-slave-common

2) Add a line with the MESOS_ATTRIBUTES environment variable (this will be read by the dcos-mesos-slave or dcos-mesos-slave-public systemd unit):

```
MESOS_ATTRIBUTES=location:bare_metal;disk_type:ssd
```

(You can specify additional attributes by separating by semicolons)

3) Remove the old slave metadata and restart the dcos-mesos-slave (or dcos-mesos-slave-public) service:

```
# Replace dcos-mesos-slave with dcos-mesos-slave-public for public agents:
sudo systemctl stop dcos-mesos-slave
sudo rm /var/lib/dcos/mesos-resources
sudo rm /var/lib/mesos/slave/meta/slaves/latest
# Replace dcos-mesos-slave with dcos-mesos-slave-public for public agents:
sudo systemctl start dcos-mesos-slave
```

4) Most likely required: if the service doesn't come up, remove `/var/lib/mesos/slave/meta/slaves/latest`:

```bash
sudo rm /var/lib/mesos/slave/meta/slaves/latest
```

## How do I change the resources for a DC/OS node?

**This will kill all tasks running on the agent**

1) Make your changes to the agent node (change number of CPUs/memory/disk, etc.)

2) Stop the agent service:

  For private agents:
  
  ```
  sudo sh -c 'systemctl kill -s SIGUSR1 dcos-mesos-slave && systemctl stop dcos-mesos-slave'
  ```

  For public agents:

  ```
  ⁠⁠⁠⁠sudo sh -c 'systemctl kill -s SIGUSR1 dcos-mesos-slave-public && systemctl stop dcos-mesos-slave-public'
  ```

3) Remove the metadata and mesos resources files (these will be re-generated on agent start):

```
sudo rm /var/lib/dcos/mesos-resources
sudo rm /var/lib/mesos/slave/meta/slaves/latest
```

4) Start the agent back up:

For private agents:

```
systemctl start dcos-mesos-slave
```

For public agents:

```
systemctl start dcos-mesos-slave-public
```

## How do I determine what version of DC/OS a specific node is on?

Look at /opt/mesosphere/etc/dcos-version.json

## What is this `jq` command I see throughout the documentation?

'jq' is an open source command-line JSON parser.  It can be found here: https://stedolan.github.io/jq/

You can quickly install it with this:

```

curl -LO https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64
chmod 755 jq-linux64
sudo cp -p jq-linux64 /usr/bin/jq

```

## My agents are complaining about certificate issues when trying to obtain items from URIs.  How do I fix this?

If you're using self-signed or custom certificates on your artifact repositories, you can configure your agents to trust them (in DC/OS 1.9.x) by completing the following:

1) Copy your custom CA cert or certificate to /var/lib/dcos/pki/tls/cert (create this directory if it does not exist already)

2) Hash your certificate, and use the hash output as the filename for a soft link to the actual certificate.

For example:

```bash

mkdir -p /var/lib/dcos/pki/tls/certs
cp test.pem /var/lib/dcos/pki/tls/certs/
cd /var/lib/dcos/pki/tls/certs/
ln -s test.pem "$(openssl x509 -hash -noout -in "test.pem")".0

```

This should result in a directory that looks roughly like this:

```bash
[root@ip-10-10-0-138 certs]# ll
total 4
lrwxrwxrwx. 1 root root    8 Apr 26 00:33 87e86989.0 -> test.pem
-rw-r--r--. 1 root root 1285 Apr 26 00:31 test.pem
```

## How do I configure the Mesos fetcher to pull data from HDFS?
Each Mesos agent needs a set of hadoop binaries present on it (configured with proper `core-site.xml` and `hdfs-site.xml`).  Additionally, you must pass in the environment variable `MESOS_HADOOP_HOME` to your mesos agent.

For example, to configure this to work with the DC/OS hdfs package, you can run something similar to the following:

```bash

# Switch to root:
sudo su -

# Download the hadoop binary package
curl -LO http://mirror.reverse.net/pub/apache/hadoop/common/hadoop-2.6.5/hadoop-2.6.5.tar.gz
# Extract it and put in /opt/hadoop
tar -xzvf hadoop-2.6.5.tar.gz
mv hadoop-2.6.5 /opt/hadoop

# Install java in case it's not already installed
yum install -y java-1.8.0-openjdk

# Download core-site.xml and hdfs-site.xml to /opt/hadoop/etc/hadoop (and back up the existing instances)
cd /opt/hadoop/etc/hadoop/
mv hdfs-site.xml hdfs-site.xml.bak-$(date +%Y%m%d-%H%M%S)
mv core-site.xml core-site.xml.bak-$(date +%Y%m%d-%H%M%S)
curl -O api.hdfs.marathon.l4lb.thisdcos.directory:80/v1/endpoints/core-site.xml
curl -O api.hdfs.marathon.l4lb.thisdcos.directory:80/v1/endpoints/hdfs-site.xml

echo "MESOS_HADOOP_HOME=/opt/hadoop/" >> /var/lib/dcos/mesos-slave-common
systemctl restart dcos-mesos-slave

```

(Source: http://mesos.apache.org/documentation/latest/configuration/)


## Why is `beam.smp` is using all my CPU?

Take a look at https://jira.mesosphere.com/browse/DCOS_OSS-2109

Try configuring your system kernel to not use 62053 for ephemeral ports (conflicts with Navstar):

```
echo "net.ipv4.ip_local_port_range = 32768    60999" >> /etc/sysctl.conf
sysctl -p /etc/sysctl.conf
```