This is a WIP.  It lists an example set of permissions that can be used to start out a customer, for four primary profiles:

* Systemwide full permissions
* Systemwide read-only permissions
* Workspace-specific full permissions
* Workspace-specific read-only permissions

# Systemwide Full Permissions
```bash
dcos:adminrouter:ops:mesos full
dcos:adminrouter:ops:slave full

dcos:adminrouter:ops:system-health full
dcos:adminrouter:ops:system-logs full
dcos:adminrouter:ops:historyservice full

dcos:adminrouter:ops:metadata full
dcos:adminrouter:ops:networking full

dcos:adminrouter:package full

dcos:mesos:agent:executor:app_id:/ full
dcos:mesos:master:executor:app_id:/ full

dcos:mesos:agent:framework:role:slave_public read
dcos:mesos:master:framework:role:slave_public read

dcos:mesos:agent:task:app_id:/ full
dcos:mesos:master:task:app_id:/ full

dcos:mesos:agent:sandbox:app_id:/ full

# I don't think this does anything?
dcos:mesos:master:marathon:app_id:/ full

dcos:adminrouter:service:marathon full
dcos:service:marathon:marathon:services:/ full

dcos:adminrouter:service:metronome full
dcos:service:metronome:metronome:jobs:/ full

# This needs to be added to documentation:
dcos:adminrouter:secrets full
# list maybe only needs read:
dcos:secrets:list:default:/ full
dcos:secrets:default:/* full
```


# Systemwide Read-Only Permissions
```bash
dcos:adminrouter:ops:mesos full
dcos:adminrouter:ops:slave full

dcos:adminrouter:ops:system-health full
dcos:adminrouter:ops:system-logs full
dcos:adminrouter:ops:historyservice full
# Should probably be full:
dcos:adminrouter:ops:metadata read
dcos:adminrouter:ops:networking full

dcos:adminrouter:package full

dcos:mesos:agent:executor:app_id:/ read
dcos:mesos:master:executor:app_id:/ read

dcos:mesos:agent:framework:role:slave_public read
dcos:mesos:master:framework:role:slave_public read

dcos:mesos:agent:task:app_id:/ read
dcos:mesos:master:task:app_id:/ read

dcos:mesos:agent:sandbox:app_id:/ read

# I don't think this does anything?
dcos:mesos:master:marathon:app_id:/ read

dcos:adminrouter:service:marathon full
dcos:service:marathon:marathon:services:/ read

# should probably be full
dcos:adminrouter:service:metronome read
dcos:service:metronome:metronome:jobs:/ read

# This needs to be added to documentation:
dcos:adminrouter:secrets read
dcos:secrets:list:default:/ read
dcos:secrets:default:/* read
```

# Permissions for Secrets (1.11.4)
The UI/UX around secrets for DC/OS 1.11.4 does not yet fully support fine-grained permissions.  

There are three types of permissions that can be granted:
* `dcos:adminrouter:secrets full` grants access to the secrets endpoint, which is necessary for any interaction with secrets
* `dcos:secrets:list:default:<some-path>` grants access to **list** a given set of secrets.  This has the following caveats:
  * `full` and `read` have the same behavior.
  * There **should** be a leading slash.  For example, `/tenant`
  * There **should not be** an asterisk.
  * Using the CLI, you will **only** be able to do a list on the granted paths.  For example:
    * User X has `dcos:secrets:list:default:/tenant read`
    * User X will receive an error for `dcos security secrets list /`
    * User X will receive a list of secrets for `dcos security secrets list /tenant`
    * There is no simple command to get a list of all secrets a given user has access to.  You must make individual queries for individual paths.
  * Using the UI, this is an all or nothing situation - you can either grant access to see a list of all secrets, or none at all.  Specifically:
    * If a user has `dcos:secrets:list:default:/ read` (or `update`), they will be able to see a list of all secrets in the system.
    * If they do not, the secrets UI will not display anything, regardless of what other secrets permissions they have
    * Note that this will grant the ability to get a list of secrets, but will not grant the ability create, view, update, or delete those secrets.  These are governed by the next permission.
* `dcos:secrets:default:<path> <action>` grants permissions to actually create/read/update/delete secrets in a given path.  This has the following caveats:
  * `<path>` needs a leading slash, and supports wildcards '*" at the end of the path.  For example:
    * `dcos:secrets:default:/tenant/secretname <action>` will grant permissions (C/R/U/D) on the secret called `/tenant/secretname`
    * `dcos:secrets:default:/tenant/* <action>` will grant permissions (C/R/U/D) on any secret in the path of `/tenant/*`
  * The API / CLI actions behave as follows:
    * In order to `create`, `read`, `update`, or `delete` a given secret, you need the corresponding action.
  * The UI has some limitations around actions:
    * In order to `read` or `update` **any** secret _through the UI_, you need `dcos:superuser full`.  This is a current limitation of the UI.
    * In order to `delete` or `create` a secret through the UI, you need the corresponding `create`/`delete` permission

So, given the above, these are some potential sets of permissions that could be granted, and how they behave:

### CLI/API Only
* CLI/API: Full access to secrets in `/tenant/*`
* UI: No access
```
dcos:adminrouter:secrets full
dcos:secrets:list:default:/tenant read
dcos:secrets:default:/tenant/* full
```

### CLI/API: 
* CLI/API: Full access to secrets in `/tenant/*`
* CLI/API: List all secrets in the system
* UI: list **all** secrets in the system, `create`/`delete` secrets in `/tenant/*`
```
dcos:adminrouter:secrets full
dcos:secrets:list:default:/ read
dcos:secrets:default:/tenant/* full
```


# Group-specific Full Permissions
```
dcos:adminrouter:ops:mesos full
dcos:adminrouter:ops:slave full

dcos:adminrouter:service:marathon full
dcos:service:marathon:marathon:services:/tenant full

dcos:mesos:agent:executor:app_id:/tenant full
dcos:mesos:master:executor:app_id:/tenant full

dcos:mesos:agent:framework:role:slave_public read
dcos:mesos:master:framework:role:slave_public read

dcos:mesos:agent:task:app_id:/tenant full
dcos:mesos:master:task:app_id:/tenant full

dcos:mesos:agent:sandbox:app_id:/tenant full

dcos:mesos:master:marathon:app_id:/tenant full
```



# Group-specific Read-Only Permissions
```
dcos:adminrouter:ops:mesos full
dcos:adminrouter:ops:slave full

dcos:adminrouter:service:marathon full
dcos:service:marathon:marathon:services:/tenant read

dcos:mesos:agent:executor:app_id:/tenant read
dcos:mesos:master:executor:app_id:/tenant read

dcos:mesos:agent:framework:role:slave_public read
dcos:mesos:master:framework:role:slave_public read

dcos:mesos:agent:task:app_id:/tenant read
dcos:mesos:master:task:app_id:/tenant read

dcos:mesos:agent:sandbox:app_id:/tenant read

dcos:mesos:master:marathon:app_id:/tenant read
```


# All Permissions:
This section indicates most all of the available permissions highlighting those that have not been included in one of the permission sets above.  These are basically permissions that *could* be added if you're still missing permissions from the above list.

There's also a very brief description of what each permission set does.
```bash
##### AdminRouter
# ACS
dcos:adminrouter:acs full

# CA
dcos:adminrouter:ops:ca:ro full
dcos:adminrouter:ops:ca:rw full

# CRDB
dcos:adminrouter:ops:cockroachdb full

# Exhibitor
dcos:adminrouter:ops:exhibitor full

# Histroy Service
# (already granted)
# dcos:adminrouter:ops:historyservice full

# Mesos-DNS API
dcos:adminrouter:ops:mesos-dns full

# Secrets (UI and API)
# (already granted)
# dcos:adminrouter:secrets full

# System Metrics API
# /system/v1/metrics/
dcos:adminrouter:ops:system-metrics full

# System health API
# (already granted)
# /system/health/v1
# dcos:adminrouter:ops:system-health full

# System logs API (already granted)
# /system/v1/logs/
# dcos:adminrouter:ops:system-logs full

# Mesos master
# (already granted)
# dcos:adminrouter:ops:mesos full

# Metadata endpoint 
# (already granted)
# /metadata
# dcos:adminrouter:ops:metadata full

# Network metrics endpoint 
# (already granted)
# networking/api/v1
# dcos:adminrouter:ops:networking full

# Mesos agent
# (already granted)
# dcos:adminrouter:ops:slave full

# Licensing API
dcos:adminrouter:licensing  full

# Cosmos API
# dcos:adminrouter:package full

# Service endpoint (no leading slash)
# /service/<other>
dcos:adminrouter:service:jenkins full

# Marathon API
# (already granted)
# /service/marathon
# dcos:adminrouter:service:marathon full

# Metronome API
# (already granted)
# /service/metronome
# dcos:adminrouter:service:metronome full

###########################################################################
##### Mesos Agent

##### Agent-wide
# raw Mesos endpoint (supports dot)
# dcos:mesos:agent:endpoint:path:/monitor/statistics.json read
dcos:mesos:agent:endpoint:path[:<endpoint>] read

# agent flag ?
dcos:mesos:agent:flags read

# Mesos agent system logs
dcos:mesos:agent:log read



# Non-TTY exec
# dcos:mesos:agent:container:app_id:/ read
dcos:mesos:agent:container:app_id[:<service-or-job-group>] read
# TTY exec
# dcos:mesos:agent:container:app_id:/ update
dcos:mesos:agent:container:app_id[:<service-or-job-group>] update

# ??? View given role
dcos:mesos:agent:framework:role[:<role-name>] read
# ??? "Controls access to the debugging features for the given Mesos role."
dcos:mesos:agent:container:role[:<role-name>] update



# Executor information
# (already granted)
# dcos:mesos:agent:executor:app_id[:<service-or-job-group>] read

# Access to sandbox
# (already granted)
# dcos:mesos:agent:sandbox:app_id[:<service-or-job-group>] read

# Access to task information
# (already granted)
# dcos:mesos:agent:task:app_id[:<service-or-job-group>] read



##### Framework permissions
# Launch child container? (group?)
dcos:mesos:agent:nested_container_session:app_id[:<service-or-job-group>] create
# Framework
# Launch child container (role?)
dcos:mesos:agent:nested_container_session:role[:<role-name>] create
# Framework
# Laucnh child container (user?)
dcos:mesos:agent:nested_container_session:user[:<linux-user-name>] create

###########################################################################
##### Mesos master

# Master-wide
# mesos master flag ?
dcos:mesos:master:flags

# Mesos master system logs
dcos:mesos:master:log

# raw Mesos endpoint ?
dcos:mesos:master:endpoint:path[:<path>]


##### executor access
# (already granted)
dcos:mesos:master:executor:app_id[:<service-or-job-group>] read


##### Create/destroy stuff
# Framework: register with role
dcos:mesos:master:framework:role[:<role-name>] create/read
# framework: tear down service with given principal
dcos:mesos:master:framework:principal[:<service-account-id>] delete

# create reservation with given role
dcos:mesos:master:reservation:role[:<role-name>] create
# destroy reservation for given principal
dcos:mesos:master:reservation:principal[:<service-account-id>] delete

# create volume for role
dcos:mesos:master:volume:role[:<role-name>] create
# destroy volume with given principal
dcos:mesos:master:volume:principal[:<service-account-id>]


##### Mesos stuff
# Access to quota?
dcos:mesos:master:quota:role[:<role-name>] read/update

# set weights for roles
dcos:mesos:master:weight:role[:<role-name>] read/update

##### Framework stuff
# framework: run task in group
dcos:mesos:master:task:app_id[:<service-or-job-group>] create

# framework: run task with user
dcos:mesos:master:task:user[:<linux-user-name>] create


###########################################################################
##### Marathon
# /service/marathon/v2/info
dcos:service:marathon:marathon:admin:config read

# /service/marathon/v2/events
dcos:service:marathon:marathon:admin:events read

# GET /service/marathon/v2/leader
dcos:service:marathon:marathon:admin:leader read
# DELETE /service/marathon/v2/leader
dcos:service:marathon:marathon:admin:leader update

# Generic: access to specific Marathon group
# dcos:service:marathon:marathon:services:/[<service-group>] full

###########################################################################
##### Metronome

# Generic: access to specific Metronome group
# dcos:service:metronome:metronome:jobs[:<job-group>] full
```
