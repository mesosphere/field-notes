# This document is a Work In Progress

# Best practices for DC/OS

This is a list of best practices for DC/OS, in no particular order.

## Critical Best Practices

#### XFS ftype
Whatever filesystems `/var/lib/docker` and `/var/lib/mesos` are on **must** be formatted with `ftype=1` (`mkfs -t xfs -n ftype=1 /dev/sdc1`).  This can be verified with something like the following:
```bash
$ xfs_info /var/lib/docker
meta-data=/dev/xvdf              isize=512    agcount=4, agsize=6553600 blks
         =                       sectsz=512   attr=2, projid32bit=1
         =                       crc=1        finobt=0 spinodes=0
data     =                       bsize=4096   blocks=26214400, imaxpct=25
         =                       sunit=0      swidth=0 blks
naming   =version 2              bsize=4096   ascii-ci=0 ftype=1
log      =internal               bsize=4096   blocks=12800, version=2
         =                       sectsz=512   sunit=0 blks, lazy-count=1
realtime =none                   extsz=4096   blocks=0, rtextents=0
```
*(Note: `ftype=1`)*

Or with this:
```bash
$ docker info | grep -A2 "Storage Driver"
Storage Driver: overlay
 Backing Filesystem: xfs
 Supports d_type: true
```

*(Note: `Supports d_type: true`)*

#### Cluster Size
You **must** have an odd number of masters.
Any production cluster **must** have at least five masters.
Any non-production cluster **must** have at least 3 masters.
The only acceptable cluster with 1 master is a local test cluster.

If you have masters spread across multiple locations (zones, buildings, racks, etc.), they **must** be spread across at least three locations.  If you cannot provision three locations, it is preferable to have one zone vs. two zones.

#### NTP or Chrony
NTP or Chrony **must** be properly configured, and **must** be properly working, with valid reachable NTP servers.  They should preferably be designated with IP addresses, not DNS names.

#### DC/OS Deployment Method
Use the advanced installer.  Do not use any of the following:
* CLI Installer
* GUI Installer
* CloudFormation Template

Also, ideally, use some CI to deploy DC/OS.

## Important Best Practices

#### Docker version
Use Docker 17.06.2 or 17.12 for DC/OS.

#### Automation
Use service accounts for authenticating against DC/OS from any automation (aside from one-time automation such as deployment).

## Other Best Practices

#### Filesystem layout
Ideally you'd have separate partitions for the following filesystem paths (WIP to distinguish masters and agents into different tables)
* `/var/lib/mesos` This is the disk space that Mesos advertises in the UI (Note: This space is rolled up if there are `MOUNT` volumes - `/dcos/volume<N>` - present)
* `/var/lib/mesos/slave/volumes` This is used by frameworks that consume `ROOT` persistent volumes
* `/var/lib/mesos/slave/store/docker` This is used to store Docker Image Layers that are used to provision UCR containers
* `/var/lib/docker` This is used to store Docker Image Layers and by Containers launched with the Docker Engine
* `/var/lib/dcos` On Masters this is where Exhibitor stores Zookeeper data, on the agents it's where persistent configuration files (`/var/lib/dcos/mesos-slave-common` and `/var/lib/dcos/mesos-resources`) are stored. Highly recommended that it be kept separate on the masters, a bit of an overkill on agents.
* `/dcos/volume<N>` (e.g., `/dcos/volume0`, `/dcos/volume1` ...) This is used by frameworks that consume `MOUNT` persistent volumes.

#### Filesystem sizing:
A common question is 'what filesystems do I need, and how large do they need to be?'

The answer to this question is always going to be 'it depends' because it's going to be heavily cluster-dependent, but the below should be enough to get you started.  Just make sure you're monitoring your specific cluster to see which partitions are consumed.
```
bootstrap node
/           Default Linux Setting (minimum 100G)
/boot       Default Linux Setting
/home       Default Linux Setting
/var        Default Linux Setting (minimum 20G)
/var/log    Default Linux Setting (minimum 20G)
/tmp        Default Linux Setting (minimum 10G)
/opt        Default Linux Setting (minimum 20G)
swap        Default Linux Setting

master nodes
/           Default Linux Setting
/boot       Default Linux Setting
/home       Default Linux Setting
/var        Default Linux Setting (minimum 20G)
/var/log    Default Linux Setting (minimum 20G)
/tmp        Default Linux Setting (minimum 10G)
/opt        Default Linux Setting (minimum 20G)
swap        Default Linux Setting
--- DC/OS-specific mounts
/var/lib/dcos       minimum 10G, should be fast (SSD or faster)
/var/lib/docker     minimum 20G

private nodes
/           Default Linux Setting
/boot       Default Linux Setting
/home       Default Linux Setting
/var        Default Linux Setting (minimum 20G)
/var/log    Default Linux Setting (minimum 20G)
/tmp        Default Linux Setting (minimum 10G)
/opt        Default Linux Setting (minimum 20G)
swap        Default Linux Setting
--- DC/OS-specific mounts
/var/lib/dcos       minimum 20G
/var/lib/docker     minimum 40G
/var/lib/mesos      minimum 40G

public nodes
/           Default Linux Setting
/boot       Default Linux Setting
/home       Default Linux Setting
/var        Default Linux Setting (minimum 20G)
/var/log    Default Linux Setting (minimum 20G)
/tmp        Default Linux Setting (minimum 10G)
/opt        Default Linux Setting (minimum 20G)
swap        Default Linux Setting
--- DC/OS-specific mounts
/var/lib/dcos       minimum 10G
/var/lib/docker     minimum 40G
/var/lib/mesos      minimum 40G
```


#### Informational
These are replicated state locations:

On the Masters, under `/var/lib/dcos`
* Mesos Paxos replicated log: `/var/lib/dcos/mesos/master/replicated_log`
* Navstar Overlay replicated log: `/var/lib/dcos/mesos/master/overlay_replicated_log`
* CockroachDB distributed database `/var/lib/dcos/cockroach`
* Navstar Mnesia distributed database: `/var/lib/dcos/navstar/mnesia`
* Navstar Lashup distributed database: `/var/dcos/navstar/lashup`
* Secrets Vault: `/var/lib/dcos/secrets/vault`
* Exhibitor Zookeeper distributed database: `/var/lib/dcos/exhibitor/zookeeper`
* History Service cache: `/var/lib/dcos/dcos-history`

On the Masters, it is *highly recommended* that `/var/lib/dcos` be hosted on a separate partition backed by *fast* _locally-attached_ storage (SSD/NVMe).

On the Agents, persistent configuration override files are stored and it is a bit of an overkill to have `/var/lib/dcos` on its own partition.
* Configuration Overrides: `/var/lib/dcos/mesos-slave-common`
* Resource Overrides: `/var/lib/dcos/mesos-resources`

On the Agents, the following directories under `/var/lib/mesos` should ideally be on distinct partitions, but if that's too much to ask, please ensure that `/var/lib/mesos` is hosted on a separate partition at the very least:
* `/var/lib/mesos/slave/slaves` - This is used to house the sandbox directories for tasks
* `/var/lib/mesos/slave/volumes` - This is used by frameworks that consume `ROOT` persistent volumes
* `/var/lib/mesos/docker/store` - This is used to store Docker Image Layers that are used to provision UCR containers

Miscellaneous directories that should be hosted on their own partitions:
* `/var/lib/docker` - This is used to store Docker Image Layers and by Containers launched with the Docker Engine
* `/dcos/volume<N>` (e.g., `/dcos/volume0`, `/dcos/volume1` ...) - This is used by frameworks that consume `MOUNT` persistent volumes.

The disk space that Apache Mesos advertises in its UI is the (sum of the) space advertised by filesystem(s) underpinning `/var/lib/mesos`

Note: This space is further rolled up if there are `MOUNT` volumes (`/dcos/volume<N>`) present

Note: `/opt/mesosphere` should also ideally be on its own partition for DC/OS 1.11 and above

All of the aforementioned filesystem paths (mount points) should ideally be on their own isolated IO path, all the way down to the physical devices to minimize the effects of noisy neighbors.

Note: The `/var/lib/mesos/slave/meta/resources`, `/var/lib/mesos/slave/volumes` & `/dcos/volume<N>` (`MOUNT` volume) directories MUST all be preserved (or restored from backups, if present) for reservations to be re-advertised to the frameworks for operations and tasks to recover successfully. (edited)

#### Secret Configuration and Locations
If you have an app at `/path/to/app`, specify the secrets used by the app at `/path/to/app/secretname`.  This encourages the best isolation of secrets from applications.
