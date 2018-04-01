---
---

## Overview

This document details some of the automation that can be used to create a cluster as code.  The DC/OS CLI tool (`dcos`) is primarily a binary wrapper around the DC/OS REST APIs; this attempts to minimize the dependency on this tool.

This document assumes that the following environment variables are set:
* `CLUSTER`: Base URL for the cluster, including protocol (e.g. https://master.dcos/ or https://54.10.10.200).
* `CLUSTER_IP`: IP address or hostname for the cluster, excluding protocol (e.g., master.dcos or 54.10.10.200).
* `TOKEN` authentication token; this is a string used to validate that the API query is authorized.  There are several ways to generate this token; you can use the DC/OS IAM (Identity and Access Management API), or you can use the dc/os CLI tool, which makes the query for you.

### API Authentication
Almost every API query against DC/OS requires an authentication token (exceptions to this include the API query used to generate the token and the API query used to obtain cluster CA certificate).

There are several ways to set up these environment variables and obtain the cluster CA certificate:

#### API Prep Using the API:
```bash
# Set up env variables.  Replace with correct username, password, and master IP
export CLUSTER_IP=10.10.0.19
export USERNAME=username
export PASSWORD=password

## Put username and password in a JSON file, to be passed to the DC/OS auth API
echo '{"uid": "USERNAME", "password": "PASSWORD"}' > login_request.json
sed -i "s/USERNAME/${USERNAME}/" login_request.json
sed -i "s/PASSWORD/${PASSWORD}/" login_request.json

## POST the JSON file to the auth login API
curl -k https://${CLUSTER_IP}/acs/api/v1/auth/login \
    -X POST \
    -H 'content-type:application/json' \
    -d @login_request.json \
    > login_token.json

## Parse the JSON response and save the token to a text file
cat login_token.json | python -c 'import sys,json;j=sys.stdin.read();print(json.loads(j))["token"]' > token
export TOKEN=$(cat token)

# Get cluster CA certificate
curl http://${CLUSTER_IP}/ca/dcos-ca.crt -o ${CLUSTER_IP}.ca.crt

## Verify that you have a token, and clean up
unset USERNAME
unset PASSWORD
rm login_request.json
rm login_token.json
rm token
```

#### API Prep Using the DC/OS CLI
If you have a local dc/os CLI and are already authenticated to the cluster, you can grab your authentication pieces from the CLI configuration.
```bash
# Set up authorization and env variables
export CLUSTER=$(dcos config show core.dcos_url)
export CLUSTER_IP=$(echo ${CLUSTER} | awk -F'/' '{print $NF}')
export TOKEN=$(dcos config show core.dcos_acs_token)

# Get cluster CA certificate
curl http://${CLUSTER_IP}/ca/dcos-ca.crt -o ${CLUSTER_IP}.ca.crt
```

## Local Users
### Create a local user using the API
```bash
export USERNAME="justin"
export PASSWORD="password"
export DESCRIPTION="Local user created through API"

tee local-user.json <<-'EOF'
{
  "description": "DESCRIPTION",
  "password": "PASSWORD"
}
EOF

sed -i "s/DESCRIPTION/${DESCRIPTION}/; s/PASSWORD/${PASSWORD}/" local-user.json

curl -L \
    --cacert ${CLUSTER_IP}.ca.crt \
    -H "authorization: token=${TOKEN}" \
    -H "content-type: application/json" \
    -X PUT \
    -d @local-user.json \
    ${CLUSTER}/acs/api/v1/users/${USERNAME}
```

### Create a group using the API
```bash
export GROUPNAME="local-admins"
export DESCRIPTION="Local group created through API"

tee local-group.json <<-'EOF'
{
  "description": "DESCRIPTION"
}
EOF

sed -i "s/DESCRIPTION/${DESCRIPTION}/" local-group.json

curl -L \
    --cacert ${CLUSTER_IP}.ca.crt \
    -H "authorization: token=${TOKEN}" \
    -H "content-type: application/json" \
    -X PUT \
    -d @local-group.json \
    ${CLUSTER}/acs/api/v1/groups/${GROUPNAME}
```

### Add a user to a group, using the API
```bash
export USERNAME="justin"
export GROUPNAME="local-admins"

curl -L \
    --cacert ${CLUSTER_IP}.ca.crt \
    -H "authorization: token=${TOKEN}" \
    -X PUT \
    ${CLUSTER}/acs/api/v1/groups/${GROUPNAME}/users/${USERNAME}
```

## LDAP

### Export LDAP Configuration (JSON) from a configured DC/OS Cluster
```bash
# View current LDAP configuration
curl -L \
    --cacert ${CLUSTER_IP}.ca.crt \
    -H "authorization: token=${TOKEN}" \
    ${CLUSTER}/acs/api/v1/ldap/config

# Save current LDAP configuration to json
curl -L \
    --cacert ${CLUSTER_IP}.ca.crt \
    -H "authorization: token=${TOKEN}" \
    ${CLUSTER}/acs/api/v1/ldap/config > ldap-${CLUSTER_IP}.json
```

### Import LDAP Configuration (JSON) into a DC/OS Cluster
```bash
# Set LDAP configuration
curl -L \
    --cacert ${CLUSTER_IP}.ca.crt \
    -H "authorization: token=${TOKEN}" \
    -H "content-type: application/json" \
    -X PUT \
    -d @ldap-${CLUSTER_IP}.json \
    ${CLUSTER}/acs/api/v1/ldap/config
```

### Test LDAP Connection
```bash
# Setup env variables for json
export USERNAME="Justin.Lee"
export PASSWORD="password123"

# Generate json
tee ldap-test.json <<-'EOF'
{
    "uid": "USERNAME",
    "password": "PASSWORD"
}
EOF

sed -i "s/USERNAME/${USERNAME}/; s/PASSWORD/${PASSWORD}/" ldap-test.json

# Test connection
curl -L \
    --cacert ${CLUSTER_IP}.ca.crt \
    -H "authorization: token=${TOKEN}" \
    -H "content-type: application/json" \
    -X POST \
    -d @ldap-test.json \
    ${CLUSTER}/acs/api/v1/ldap/config/test
```

You should see a result that looks like this:
```json
{
  "description": "Directory back-end reached and all tests passed.",
  "code": "TEST_PASSED"
}
```

## Import a single user from LDAP
You can use the API to import a user into DC/OS.  Note that this user will by default have no permissions (they will be able to authenticate but not access anything)
```bash
# Set up env variable for user to be imported
export USERNAME=Justin.Lee

# Generate json
tee ldap-import.json <<-'EOF'
{
    "username": "USERNAME"
}
EOF

sed -i "s/USERNAME/${USERNAME}/" ldap-import.json

# 
curl -L \
    --cacert ${CLUSTER_IP}.ca.crt \
    -H "authorization: token=${TOKEN}" \
    -H "content-type: application/json" \
    -X POST \
    -d @ldap-import.json \
    ${CLUSTER}/acs/api/v1/ldap/importuser
```

### Import a group from LDAP
You can also use the API to import a user into DC/OS.  This will import all users in that group in LDAP into a DC/OS group of the same name.  Note that this group will by default have no permissions (they will be able to authenticate but not access anything).
```bash

# Set up env variable for user to be imported
export GROUPNAME=Administrators

# Generate json
tee ldap-group-import.json <<-'EOF'
{
    "groupname": "GROUPNAME"
}
EOF

sed -i "s/GROUPNAME/${GROUPNAME}/" ldap-group-import.json

# Trigger the import
curl -L \
    --cacert ${CLUSTER_IP}.ca.crt \
    -H "authorization: token=${TOKEN}" \
    -H "content-type: application/json" \
    -X POST \
    -d @ldap-group-import.json \
    ${CLUSTER}/acs/api/v1/ldap/importgroup
```

### Permissions
Permissions in DC/OS have several characteristics:
* Once a user has authenticated to the DC/OS cluster (either via a local user or through LDAP), permissions are handled identically.
* Permissions are granted through the use of permissions strings, also known as "Access Control Entries (ACEs), each formatted as `dcos:<enforcer>:permissions:path <create/read/update/delete/full>`.  For example, the following are examples valid permission strings:
    * `dcos:superuser full`
    * `dcos:adminrouter:ops:slave read`
* Permissions are additive.  Adding additional permissions to a user or group will only increase their access.  A given permission string can not be used to remove or revoke permissions grant by a different permission string.
* Permissions can be granted on both a per-user basis a a per-group basis.  
    * For example, assume the following:
        * User group "Admin" has permissions W and X
        * User group "Production" has permissions X and Y
        * User "Justin" has permission Z
        * User "Justin" is also in groups "Admin" and "Production"
    * Then, user "Justin" would have permissions W, X, Y, and Z

In order to grant a permission (ACE) to a given user or group, two actions must take place:
* The ACE must be created.  By default, the only permissions that "exist" in the system are those that are granted to built-in service accounts; most permissions that would be granted to individual users or user groups must be manually created.
* The user or group must be added to the ACE.

```bash
# Set up environment variables
export USERNAME=justin
export GROUPNAME=administrators

export PERMISSION_STRING="dcos:service:marathon:marathon:services:/app"
export PERMISSION_ACTION="read"
export DESCRIPTION="Access to the '/app' Marathon group"

# ACEs exist as REST endpoints, so any slashes must be escaped prior to creation
export PERMISSION_STRING_ESCAPED=$(echo ${PERMISSION_STRING} | sed "s/\//%252F/")
export DESCRIPTION_ESCAPED=$(echo ${DESCRIPTION} | sed "s:\/:\\\/:g")

```

##### Create the ACE endpoint (will fail harmlessly if the ACE already exists)
```bash
tee ace.json <<-'EOF'
{
  "description": "DESCRIPTION_ESCAPED"
}
EOF

sed -i "s/DESCRIPTION_ESCAPED/${DESCRIPTION_ESCAPED}/" ace.json

curl -L \
    --cacert ${CLUSTER_IP}.ca.crt \
    -H "authorization: token=${TOKEN}" \
    -H "content-type: application/json" \
    -X PUT \
    -d @ace.json \
    ${CLUSTER}/acs/api/v1/acls/${PERMISSION_STRING_ESCAPED}
```

#### Add a user to the ACE, with the "read" action
```bash
curl -L \
    --cacert ${CLUSTER_IP}.ca.crt \
    -H "authorization: token=${TOKEN}" \
    -X PUT \
    ${CLUSTER}/acs/api/v1/acls/${PERMISSION_STRING_ESCAPED}/users/${USERNAME}/${PERMISSION_ACTION}
```

#### Add a group to the ACE, with the "read" action
```bash
curl -L \
    --cacert ${CLUSTER_IP}.ca.crt \
    -H "authorization: token=${TOKEN}" \
    -X PUT \
    ${CLUSTER}/acs/api/v1/acls/${PERMISSION_STRING_ESCAPED}/groups/${GROUPNAME}/${PERMISSION_ACTION}
```