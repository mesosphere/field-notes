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
echo MESOS_RESOURCES=\'$(curl -s $(hostname -i):5051/state.json | jq -c '.unreserved_resources_full' | sed 's/,/, /g; s/:/: /g' )\' | sudo tee -a /var/lib/dcos/mesos-resources
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

## How do I set up custom fault domains in my environment?
Fault domains are detected by running a script on each node (similar to ip-detect).

This script should output JSON as a single line, formatted roughly like this:
```json
{"fault_domain":{"region":{"name": "aws/us-west-2"},"zone":{"name": "aws/us-west-2a"}}}
```

The contents should have roughly these (prefer single-line, not 100% sure this is necessary but probably not a bad practice):
```json
{
  "fault_domain": {
    "region": {
      "name": "<name-of-region>"
    },
    "zone": {
      "name": "<name-of-zone>"
    }
  }
}
```

If, for example, you have a hostname convention where the first four characters identify the datacenter and the next four characters identify physical vs virtual, such as the following:
tx15physagent02: tx15 datacenter, physical
tx15virtagent02: tx15 datacenter, virtual
tx20physagent02: tx20 datacenter, physical

Then you could set up a fault domain script (placed in `genconf/fault-domain-detect`, that gets propagated to `/opt/mesosphere/bin/detect_fault_domain`) that looks like this (assuming that /etc/hostname contains your hostname):

```bash
#!/bin/bash
HOSTNAME_FILE=/etc/hostname
REGION=$(cat ${HOSTNAME_FILE} | head -c4)
ZONE=$(cat ${HOSTNAME_FILE} | head -c4)-$(cat ${HOSTNAME_FILE} | head -c8 | tail -c4)
echo "{\"fault_domain\":{\"region\":{\"name\": \"${REGION}\"},\"zone\":{\"name\": \"${ZONE}\"}}}"
```

This would result in these JSON outputs:
* tx15physagent02: `{"fault_domain":{"region":{"name": "tx15"},"zone":{"name": "tx15-phys"}}}` 
* tx15virtagent02: `{"fault_domain":{"region":{"name": "tx15"},"zone":{"name": "tx15-virt"}}}`
* tx20physagent02: `{"fault_domain":{"region":{"name": "tx20"},"zone":{"name": "tx20-phys"}}}`

More generically then the above, populate REGION with your region and ZONE with your zone, and use the same echo as above.

*It is not strictly required that the zone name include the region name, but it may be useful for clarity's sake.*

## Example ip-detect script
The fault domain detect script should be placed in `genconf/ip-detect` and gets propagated to `/opt/mesosphere/bin/detect_ip`.

This should, in my experience, work in most environments (even in environments without Internet access - this doesn't actually rely on 8.8.8.8 reachability) to identify the primary IP:

```bash
#!/bin/bash
ip route get 8.8.8.8 | awk 'NR==1{print $NF}'
```

*In my experience, it does not matter whether this outputs an endline or not.*

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

## How come I can't use the `dcos security`, `dcos backup`, or `dcos license` command?

*Note: Starting from DC/OS 1.13, these commands are installed automatically during `dcos cluster setup` or with `dcos package install dcos-enterprise-cli --cli`.*

The `dcos security` command comes from the dcos-enterprise-cli Universe package, and can be installed by running `dcos package install dcos-enterprise-cli --cli`.  Note that the features of this CLI add-on will only work with the Enterprise edition of DC/OS.

## How do I install the `dcos-enterprise-cli` package in a local universe cluster?

*Note: Starting from DC/OS 1.13, it is recommended to rely on the [bootstrap registry](https://docs.mesosphere.com/1.13/administering-clusters/repo/package-registry/quickstart/#remove-the-universe-repository-optional) to install `dcos-enterprise-cli`. Once you've removed the Universe repository, any CLI user will automatically get the enterprise plugin when running `dcos cluster setup` or `dcos package install dcos-enterprise-cli --cli`.*

Installing packages relies on the place actually doing the installation being able to reach the local universe.  If you're following the default local universe instructions, you'll end up placing the local universe on your masters on master.mesos, and it is unlikely that the place you are running the `dcos` CLI tool from (your laptop, the bootstrap) actually knows how to resolve master.mesos.  Often, it will also be firewalled off.

Here's the workaround.

1. Identify the latest relevant dcos-enterprise CLI package for your client.
    * Go to https://github.com/mesosphere/universe/tree/version-3.x/repo/packages/D/dcos-enterprise-cli
    * Dig into the subdirectories, and look at package.json to identify the highest iteration that meets your DC/OS version (`minDcosReleaseVersion`).  For example, as of 4/10/2018:
      * DC/OS 1.11: Release 18 (https://github.com/mesosphere/universe/blob/version-3.x/repo/packages/D/dcos-enterprise-cli/18/package.json)
      * DC/OS 1.10: Release 15 (https://github.com/mesosphere/universe/blob/version-3.x/repo/packages/D/dcos-enterprise-cli/15/package.json)
    * In that particular release directory, lookat resource.json, and look in the path `.cli.binaries.<platform>.x86-64.url`.  For example, as of 4/10/2018, for DC/OS 1.11.0 installing the DC/OS Enterprise CLI subcommand package on a Linux client, I would use these:
      * Linux: `https://downloads.mesosphere.io/cli/binaries/linux/x86-64/1.4.3/5f9f28ba39bec883a3f82d652a549dc06138f77b81c71aa6417d95d4024e55b7/dcos-enterprise-cli` (ref: https://github.com/mesosphere/universe/blob/version-3.x/repo/packages/D/dcos-enterprise-cli/18/resource.json#L14)
      * OSX: `https://downloads.mesosphere.io/cli/binaries/darwin/x86-64/1.4.3/c934ddb9624c27ad7723d234edb7fc9060d8a70dc43f5c7f99855c63dae0aac8/dcos-enterprise-cli` (ref: https://github.com/mesosphere/universe/blob/version-3.x/repo/packages/D/dcos-enterprise-cli/18/resource.json#L26)
2. cURL / wget / otherwise transfer the relevant file (which is a zip file) to the computer/server where your `dcos` CLI tool is:

    ```bash
    [tmp]$ curl -LO https://downloads.mesosphere.io/cli/binaries/linux/x86-64/1.4.3/5f9f28ba39bec883a3f82d652a549dc06138f77b81c71aa6417d95d4024e55b7/dcos-enterprise-cli
      % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                    Dload  Upload   Total   Spent    Left  Speed
    100 25.3M  100 25.3M    0     0  66.6M      0 --:--:-- --:--:-- --:--:-- 66.7M

    [tmp]$ ls -alh
    total 26M
    drwxrwxr-x. 2 centos centos   32 Apr 10 12:14 .
    drwx------. 8 centos centos 4.0K Apr 10 12:14 ..
    -rw-rw-r--. 1 centos centos  26M Apr 10 12:14 dcos-enterprise-cli
    ```

3. Unzip the file.  Note that in OSX, it *may* include additional unrelated files:

    ```bash
    $ unzip dcos-enterprise-cli 
    Archive:  dcos-enterprise-cli
      creating: bin/
      inflating: bin/dcos-security       
      inflating: bin/dcos-backup         
      inflating: bin/dcos-license 
    ```

4. Make sure the binaries all have the execute bit (they probably do by default):

      ```bash
      $ chmod +x bin/dcos-*
      ```

4. Make the directory `~/.dcos/subcommands/dcos-enterprise-cli/env/bin`, and place the `dcos-*` binaries in it:

    ```bash
    $ mkdir -p ~/.dcos/subcommands/dcos-enterprise-cli/env/bin
    $ cp -pv bin/dcos-* ~/.dcos/subcommands/dcos-enterprise-cli/env/bin/
    ‘bin/dcos-backup’ -> ‘/home/centos/.dcos/subcommands/dcos-enterprise-cli/env/bin/dcos-backup’
    ‘bin/dcos-license’ -> ‘/home/centos/.dcos/subcommands/dcos-enterprise-cli/env/bin/dcos-license’
    ‘bin/dcos-security’ -> ‘/home/centos/.dcos/subcommands/dcos-enterprise-cli/env/bin/dcos-security’
    [centos@ip-10-10-0-26 tmp]$ ll ~/.dcos/subcommands/dcos-enterprise-cli/env/bin

    $ ls -alh ~/.dcos/subcommands/dcos-enterprise-cli/env/bin
    total 33M
    drwxrwxr-x. 2 centos centos   63 Apr 10 12:24 .
    drwxrwxr-x. 3 centos centos   16 Apr 10 12:23 ..
    -rwxr-xr-x. 1 centos centos  11M Feb 13 13:45 dcos-backup
    -rwxr-xr-x. 1 centos centos  14M Feb 13 13:50 dcos-license
    -rwxr-xr-x. 1 centos centos 8.6M Feb 13 13:56 dcos-security
    ```

5. Profit:

    ```
    $ dcos
    Command line utility for the Mesosphere Datacenter Operating
    System (DC/OS). The Mesosphere DC/OS is a distributed operating
    system built around Apache Mesos. This utility provides tools
    for easy management of a DC/OS installation.

    Available DC/OS commands:

      auth           	Authenticate to DC/OS cluster
      backup         	Access DC/OS backup functionality
      cluster        	Manage your DC/OS clusters
      config         	Manage the DC/OS configuration file
      help           	Display help information about DC/OS
      job            	Deploy and manage jobs in DC/OS
      license        	Manage your DC/OS licenses
      marathon       	Deploy and manage applications to DC/OS
      node           	View DC/OS node information
      package        	Install and manage DC/OS software packages
      security       	DC/OS security related commands
      service        	Manage DC/OS services
      task           	Manage DC/OS tasks

    Get detailed command description with 'dcos <command> --help'.
    ```

*Note: The above steps install the `security`, `backup`, and `license` tools for all clusters your account communicates with.  You can also set the above up on a per-cluster basis by using the directory `~/.dcos/clusters/<cluster-id>/subcommands/dcos-enterprise-cli/env/`.  For example: `~/.dcos/clusters/9e1a0745-99bc-41f4-a4f1-7dc978fae438/subcommands/dcos-enterprise-cli/env/`*

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

## What is the format used to specify constraints in SDK frameworks?
SDK frameworks (Kafka, Elastic, Cassandra, Datastax Enterprise, Confluent Kafka, HDFS, Edge-LB, and others) support the same types of node placement constraints as Marathon does, but the format is slightly different.  Everything should be a flat string, with elements of a constraint separated by colons (`:`) and separate constraints separated by commas (`,`).  If you have multiple constraints, all constraints must be met for a pod to be placed on a node.

For example, one of these is often the default constraint (you should generally keep this, unless you have a specific reason to remove it):
* `hostname:UNIQUE`
* `hostname:MAX_PER:1`

If you wanted to add an additional LIKE constraint, using a REGEX:
* `hostname:UNIQUE;hostname,LIKE:10.0.0.[35|36|37]`
* `hostname:MAX_PER:1,type:LIKE:persistent`

If you wanted a third constraint:
* `hostname:UNIQUE;hostname,LIKE:10.0.0.[35|36|37],type:LIKE:baremetal`



## How do I change the resources for a DC/OS node?

**This will kill all tasks running on the agent**
*As of DC/OS 1.11, you can increase the number of resources on a node without doing all of this; you just have to increase the resource and restart `dcos-mesos-slave` (or turn the machine back on, if you can't increase resources dynamically).  If you are decreasing the resource, you must still follow this process*

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