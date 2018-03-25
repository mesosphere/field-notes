# DC/OS CPU/Memory Allocation and Utilization

## CPU Behavior

Between 1.9 and 1.10, Mesosphere changed the default behavior for containers run with the Docker runtime.  Specifically, in 1.10, containers run with the Docker runtime now respect the `MESOS_CGROUPS_ENABLE_CFS` flag, which defaults to true.  This means that by default in `1.10.x` and above, containers run with the Docker containerizer will be hard limited to their specified allocation.

| DC/OS Version | Mesos Containerizer Default Behavior | Docker Default Behavior |
| ---------------| ------------------------------------ | ----------------------- |
| 1.9 | Hard CPU Limit | Soft CPU Limit |
| 1.10 | Hard CPU Limit | Hard CPU Limit |

* Hard CPU Limit: Containers will be prevented from using more CPU than specified in their allocation.
* Soft CPU Limit: Containers will be allowed to use more CPU than specified in their allocation.

### Changing CPU limits in 1.10
In 1.10 and above, in order to revert to soft limits, you can do the following:

* Create and/or edit the `/var/lib/dcos/mesos-slave-common` file on an agent
* Add this line: 
```
MESOS_CGROUPS_ENABLE_CFS=false
```
* Restart the Mesos slave.  This will not result in a new Mesos agent ID.

*This will apply to both the Docker containerizer and the Mesos containerizer*

This will result in the following configuration:

| DC/OS Version | Mesos Containerizer Default Behavior | Docker Default Behavior |
| ---------------| ------------------------------------ | ----------------------- |
| 1.10 (Modified) | Soft CPU Limit | Soft CPU Limit |

***

For the purposes of testing load, some variant of this cmomand will be used (this one loads four full cores).

```bash
for i in 1 2 3 4; do yes > /dev/null & done; tail -f /dev/null;
```

***

The rest of this document refers to DC/OS versions prior to 1.10.

# DC/OS Container Runtimes

DC/OS supports two primary 'container runtimes':

* Docker Engine: Containers can be deployed using the standard Docker engine (Docker daemon), which runs on all nodes.

* Mesos Runtime (Mesos 'containerizer'): this uses standard Linux capabilities (such as cgroups) to containerize processes.  This has two main modes: 
    * Direct Mesos containerizer: this allows users to run linux processes (scripts, commands, binaries) inside a Mesos 'container' which provides cgroup (and other) isolation.
    * Universal Container Runtime (UCR): this allows users to run Docker images directly in the Mesos runtime outside of the Docker daemon

When a Marathon service is deployed (via JSON definition, or via the UI which translates to a JSON definition), it is configured with a 'cpus' field.  This is used in two different places:

* For task placement: Mesos is aware of how many CPUs are available on a given node, and tracks the sum of all tasks' "cpus" property that have been deployed to that node.  This is used to determine how much CPU time is unallocated on a given node.

    * For example, if a node has eight (8) CPUs, and four (4) tasks have been placed on that node, each with 0.5 CPUs, then from the Mesos perspective, there are six (6) CPUs available (8 - 4 * 0.5) = 8 - 2 = 6.  It will offer up to 6 CPUs in its resource offers to various frameworks.

* For configuration of the actual process that gets run on the node.  Depending on the containerizer, this behaves in different ways.

*Task placement and process configuration both rely on the "cpus" field, but use the value in completely different ways.*

**This document discusses the behavior of tasks after they are placed (i.e., the way tasks are actually configured and run).**

# Docker Engine / Containerizer

When a Marathon service is deployed with the property "container" > "type" > "DOCKER", then the service will use the Docker daemon to run the Docker image.  The "cpus" property then gets translated as a Docker --cpu-shares parameter.  

Specifically, the number in "cpus" is multiplied by 1024, and then used in the docker run command.  For example, this Marathon app definition (trimmed down):

```json
{
 "id": "/load",
 "cmd": "for i in 1 2 3 4; do yes > /dev/null & done; tail -f /dev/null;",
 "instances": 1,
 "cpus": 0.25,
 "mem": 128,
 "container": {
   "type": "DOCKER",
   "docker": {
     "image": "alpine",
     "privileged": false,
     "forcePullImage": false
   }
 }
}
```

Will result in roughly this Docker daemon command (formatted for clarity):

```bash
docker -H unix:///var/run/docker.sock run \
--cpu-shares 256 \
--memory 134217728 <...> \
alpine \ 
-c for i in 1 2 3 4; do yes > /dev/null & done; tail -f /dev/null;
```

(Note that 0.25 * 1024 = 256)

At this point, we're just using the Docker --cpu-shares property, which has this definition (from Docker documentation https://docs.docker.com/engine/admin/resource_constraints/):

> Set this flag to a value greater or less than the default of 1024 to increase or reduce the container’s weight, and give it access to a greater or lesser proportion of the host machine’s CPU cycles. This is only enforced when CPU cycles are constrained. When plenty of CPU cycles are available, all containers use as much CPU as they need. In that way, this is a soft limit. --cpu-shares does not prevent containers from being scheduled in swarm mode. It prioritizes container CPU resources for the available CPU cycles. It does not guarantee or reserve any specific CPU access.

## Docker Engine Default Behavior (Default to soft CPU limits)

**By default, tasks deployed with the Docker engine are configured with soft CPU limits.  This means that when additional CPU time is available on the node that a task is running on, the task will be allowed to utilize the additional CPU time**

Specifically:
* Assuming there is no resource contention, processes are free to use as much CPU as they want (specifically, as many cpu cycles as they want)
* When there is resource contention, processes will use CPU shares proportional to the total number of all --cpu-shares settings.

Here are some example situations, assuming one node with four (4) CPUs available:

* No resource contention:
    * Given that there are two tasks configured
        * Task 1 ("cpus": 1, or 1024 cpu-shares)
        * Task 2 ("cpus": 0.5 or 512 cpu-shares)
    * If both tasks are CPU greedy, the first task will get two thirds (1024 / (512 + 1024)), or approximately 2.66 CPUs, of available CPU cycles and the second task will get one third of available CPU cycles, or approximately 1.33 CPUs:
        * Task 1: 2.66 CPUs (⅔ of 4)
        * Task 2: 1.33 CPUs (⅓ of 4)
    * If the first task is greedy but the second task only actually needs 0.5 CPUs, then the allocation will break down as follows:
        * Task 1: 3.5 CPUs (all remaining)
        * Task 2: 0.5 CPUs (required)

* If another task gets added later on: Greedy Task 3 ("cpus": 1, or 1024 cpu-shares), then there are a total of 2560 cpu-shares (1024 + 1024 + 512) and the other tasks get throttled back to these:
    * Three greedy tasks:
        * Task 1: 1.6 CPUs (4 * 1024 / 2560)
        * Task 2: 0.8 CPUs (4 * 512 / 2560)
        * Task 3: 1.6 CPUs (4 * 1024 / 2560)
    * Greedy Task 1 and Greedy Task 3:
        * Task 1: 1.75 (half of remaining)
        * Task 2: 0.5 CPUs (less than proportional share, but all required)
        * Task 3: 1.75 (half of remaining)

* If a fourth task gets added that is allocated 1.5 CPUs (the remaining number of "available" cpus), then it will get 1536 cpu-shares (4096 total), and all the tasks will get throttled down to their allowed CPUs:
    * Greedy Task 1, 3, 4:
    * Task 1: 1 CPUs (4 *1024 / 4096)
    * Task 2: 0.5 CPUs (4 * 512 / 4096)
    * Task 3: 1 CPUs (4 * 1024 / 4096)
    * Task 4: 1.5 CPUs (4 * 1536 / 4096)

Here's the takeaway: If you are using the Docker daemon and give a task X cpus, then that task will never be prevented from using that much CPU.  It may be able to use additional unutilized CPUs.
* In a non-contention situation, the task will be allowed to use as much CPU as is available.  
* In a partial contention situation, tasks will be throttled back but will be guaranteed at least their proportional share of available CPUs
* If a full contention situation, tasks will be throttled back to their proportional share of available CPUs, which will match their full CPUs.

One other note: when viewed in the Mesos UI, an additional 0.1 CPU may show up as allocated to the task (for use by the command executor).  This does not affect either placement or Docker daemon behavior.


## Docker Engine Modified Behavior (Configure to hard CPU limits)

In addition to the above, users can pass additional Docker parameters to the Docker runtime through the Marathon app definition.  For example, to use the 'cpus' parameter (available in Docker 1.13 and above), the Marathon app definition could be modified as follows:

```json
{
 "id": "/load",
 "cmd": "for i in 1 2 3 4; do yes > /dev/null & done; tail -f /dev/null;",
 "instances": 1,
 "cpus": 0.25,
 "mem": 128,
 "container": {
   "type": "DOCKER",
   "docker": {
     "image": "alpine",
     "privileged": false,
     "parameters": [
        { "key": "cpus", "value":"0.25" }
     ],
     "forcePullImage": false
   }
 }
}
```

The above would modify the Docker command to be this:

```bash
docker -H unix:///var/run/docker.sock run \
--cpu-shares 256  \
--memory 134217728 <...> \
--cpus=0.25 <...> \
alpine \
-c for i in 1 2 3 4; do yes > /dev/null & done; tail -f /dev/null;;
```

Then, this container would be guaranteed to be limited using CPU cycles equivalent to 25% of a core.  For Docker 1.12 and below, this  could be accomplished with this set of parameters:

```json
     "parameters": [
        { "key": "cpu-period", "value":"100000" },
        { "key": "cpu-quota", "value":"25000" }
```

## Docker Engine Memory Behavior (hard limit)

When tasks (Docker images) are launched with the Docker containerizer, they are provided a specific amount of memory (in the "mem" property of the Marathon json definition, which is provided in MB).  This gets translated to a --memory flag on the Docker run command, in bytes (see above).

This is a hard limit.  Specifically, if the container tries to use more than this amount of memory, the container will be killed with an error code of 137 (out of memory).  This error can also be observed by running docker inspect.

If you desire soft limits (or other behavior), additional Docker parameters could be passed to the Docker daemon (see https://docs.docker.com/engine/admin/resource_constraints/)


# Universal Container Runtime / Mesos Containerizer
When a Docker image is deployed using the Universal Container Runtime (UCR), it runs within the Mesos containerizer.  From a CPU allocation perspective, the Mesos containerizer and the UCR behave the same.

## Mesos Containerizer / UCR Default Behavior (Default to hard CPU limits)

When a container is run with either the UCR or the Mesos containerizer, it is assigned a CPU share of ("cpus" + 0.1) (to cover the containerizer overhead).  This 0.1 CPU does NOT affect the placement algorithm.

For example, if the following service is deployed:

```json
{
 "id": "/load3",
 "cmd": "yes > /dev/null",
 "instances": 1,
 "cpus": 0.001,
 "mem": 128,
 "disk": 0,
 "container": {
   "type": "MESOS",
   "docker": {
     "image": "alpine"
   }
 }
}
```

Then the service will be throttled to 0.101 cpu cycles equivalent to 0.101 CPUs.

Note that this shows up in the Mesos UI and by monitoring the process, but does not show up in the DC/OS UI or in the Mesos state.json.  As noted above, the 0.001 cpus will also be used for placement (not 0.101).

## 1.9 Mesos Containerizer / UCR Alternate Behavior (Configure to soft CPU limits)
If you desire the soft limit behavior (limit only under contention) in Mesos Containerizer / UCR, you can make the following change on a per-slave basis:

Add this line to /run/dcos/etc/mesos-slave, /run/dcos/etc/mesos-slave-common, or /var/lib/dcos/mesos-slave-common:

> MESOS_CGROUPS_ENABLE_CFS=false

Then restart dcos-mesos-slave (replace slave with slave-public for public slaves):

```bash
systemctl stop dcos-mesos-slave
sudo rm -f /var/lib/mesos/slave/meta/slaves/latest
systemctl start dcos-mesos-slave)
```

## 1.9 Mesos Containerizer / UCR Memory Alternate Behavior (allow swap)
By default, the Mesos containerizer will allow the container to swap past the specified memory limit.  If you desire to change this behavior, you can explicitly disable swap with this flag:

> MESOS_CGROUPS_LIMIT_SWAP=true

This should be placed in the same place that the MESOS_CGROUPS_ENABLE_CFS flag would be placed (see section above).