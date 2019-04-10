Start by reading this documentation:
http://mesos.apache.org/documentation/latest/maintenance/#how-does-it-work

Tested with DC/OS 1.11.4 (Mesos 1.5.1, Marathon 1.6.535), in strict mode.

Basically, there are three modes for a node in Mesos:

* UP - Will start new tasks, running tasks will continue to run
* DRAIN - Will not start new tasks (for frameworks that respect maintenance, see below), running tasks will continue to run
* DOWN - Will kill all tasks, will not start new tasks

You can move from UP to DRAIN by scheduling maintenance, and you can move back to UP from DRAIN by unscheduling maintenance.
* Scheduling maintenance (i.e., moving to DRAIN) will not stop running tasks, but will prevent properly configured frameworks from starting new tasks on the node(s)
* Unscheduling maintenance (i.e., moving back to UP) will not affect running tasks

The only way to get to DOWN is to first put a node in DRAIN first (you can do this at the same time with multiple queries).

Once a node is DOWN, you can only move it back to UP.

These are the four valid transitions:
* Schedule maintenance (by making an "UPDATE_MAINTENANCE_SCHEDULE" API call): Move from UP to DRAIN
* Unschedule maintenance (by making an "UPDATE_MAINTENANCE_SCHEDULE" API call): Move from DRAIN to UP
* Start maintenance (by making a "START_MAINTENANCE" API call): Move from DRAIN to DOWN
* Complete maintenance (by making a "STOP_MAINTENANCE" API call): Move from DOWN to UP

## Respecting maintenance:

A framework must respect maintenance mode in order for DRAIN to do anything (putting a node in DOWN / starting maintenance will always evict running tasks, regardless of support for maintenance).

Marathon 1.6.535 (in DC/OS 1.11.4) supports respecting maintenance mode, but it must be turned on via flag.  This can be done by doing the following:

```bash
sudo mkdir -p /var/lib/dcos/marathon
sudo tee /var/lib/dcos/marathon/environment <<-'EOF'
MARATHON_ENABLE_FEATURES=vips,task_killing,external_volumes,secrets,gpu_resources,maintenance_mode
EOF
```

This adds the `maintenance_mode` to the list of enabled features.  Note that this overrides the default enabled feature list in DC/OS 1.11.4, which has `vips,task_killing,external_volumes,secrets,gpu_resources`

You can create this file prior to installing DC/OS (I think permissions will just kind of work, not entirely sure though).

This should not be necessary in Marathon 1.7 (DC/OS 1.12.x).

## API Calls

Here are some example calls to perform various actions:

All of these go through the DC/OS Master IP (in this case, 172.31.47.190), using HTTPS and the mesos/api/v1 endpoint (which is the Mesos "V1 Operator" API endpoint)

Get the current state of maintenance (will indicate which nodes are currently in drain and which are down):

```bash
curl \
    -H "authorization: token=$(dcos config show core.dcos_acs_token)" \
    -kL \
    -X POST \
    -H "content-type: application/json" \
    https://172.31.47.190/mesos/api/v1 \
    -d '{ "type": "GET_MAINTENANCE_STATUS" }'
```

Get the current list of maintenance schedules:

```bash
curl \
    -H "authorization: token=$(dcos config show core.dcos_acs_token)" \
    -kL \
    -X POST \
    -H "content-type: application/json" \
    https://172.31.47.190/mesos/api/v1 \
    -d '{ "type": "GET_MAINTENANCE_SCHEDULE" }'
```

Update the current list of maintenance schedules.  Note that this has a couple things:

* If you submit a list of schedules, it will overwrite any existing schedules
* If you update to an empty list or a list that doesn't have a schedule that was previously there, it is 'unscheduling maintenance'
* You can have multiple schedules.  Each schedule will have an period (start time in UTC nanoseconds and duration), and a list of machines that it applies to.  Hostname and IP must match, and must be the IP of the relevant nodes.

```bash
curl \
    -H "authorization: token=$(dcos config show core.dcos_acs_token)" \
    -kL \
    -X POST \
    -H "content-type: application/json" \
    https://172.31.47.190/mesos/api/v1 \
    -d '
    {
        "type": "UPDATE_MAINTENANCE_SCHEDULE",
        "update_maintenance_schedule": {
            "schedule": {
                "windows": [
                    {
                        "machine_ids": [
                            {
                                "hostname": "172.31.18.234",
                                "ip": "172.31.18.234"
                            }
                        ],
                        "unavailability": {
                            "start": { "nanoseconds": 1554905650000000000 },
                            "duration": { "nanoseconds": 3600000000000 }
                        }
                    }
                ]
            }
        }
    }'
```

For example, to unschedule all schedules:

```bash
curl \
    -H "authorization: token=$(dcos config show core.dcos_acs_token)" \
    -kL \
    -X POST \
    -H "content-type: application/json" \
    https://172.31.47.190/mesos/api/v1 \
    -d '
    {
        "type": "UPDATE_MAINTENANCE_SCHEDULE",
        "update_maintenance_schedule": {
            "schedule": {
                "windows": [
                ]
            }
        }
    }'
```

This starts maintenance (puts nodes in DOWN) for one or more nodes:

```bash
curl \
    -H "authorization: token=$(dcos config show core.dcos_acs_token)" \
    -kL \
    -X POST \
    -H "content-type: application/json" \
    https://172.31.47.190/mesos/api/v1 \
    -d '
    {
        "type": "START_MAINTENANCE",
        "start_maintenance": {
            "machines": [
                {
                    "hostname": "172.31.18.234",
                    "ip": "172.31.18.234"
                }
            ]
        }
    }'
```

This stops maintenance (brings nodes back to UP) for one or more nodes:

```bash
curl \
    -H "authorization: token=$(dcos config show core.dcos_acs_token)" \
    -kL \
    -X POST \
    -H "content-type: application/json" \
    https://172.31.47.190/mesos/api/v1 \
    -d '
    {
        "type": "STOP_MAINTENANCE",
        "stop_maintenance": {
            "machines": [
                {
                    "hostname": "172.31.18.234",
                    "ip": "172.31.18.234"
                }
            ]
        }
    }'
