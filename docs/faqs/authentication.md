---
---

# Overview

This document details a couple different methods for authenticating with DC/OS EE, without the DC/OS cli tool.

## Authentication Mechanism
DC/OS uses JWTs (JSON Web Tokens) to handle authentication.  Specifically, in order to interact with any secured DC/OS endpoint, the client or user is expected to provide proof of identity with an RS256 encoded JWT, known as an "Authorization Token".  Each authorization token has the following items as its JWT payload:

* "uid": User ID associated with the user or service account.
* "exp": Unix epoch time-formatted time, indicating how long the token is valid for.

*** 

*When authenticating against a DC/OS REST API, the **Authorization Token** should be provided in a header formatted as `"authorization: token=<token>"`.*

*For example, if an account had a token that looked `eyJ0eXAiOiJK...`, then a cURL command to access the mesos state might look something like this: `curl -k http://10.10.0.36/mesos/master/state-summary -H "authorization: token=eyJ0eXAiOiJK..."`*

***

There are two primary ways to obtain authorization tokens from the DC/OS Access Control Service (ACS) API:

1. With a local account (username/password): You can authenticate against the DC/OS ACS API with a username and password.  **This is primarily for manual interaction with the DC/OS API endpoints**, for the following reason:
  * There is relatively high computational overhead involved with invoking the API with a username/password.  If you have a service repeatedly authenticating with the DC/OS API with a username and password, it is possible to DoS the IAM API.


2. With a service account: If a service account has been set up in DC/OS, the private key associated with the service account can be used to generate a *short-lived* JWT **Login Token** (distinct from an **Authorization Token**).  
  * This Login Token can then be used to authenticate against the DC/OS ACS API to generate a *long-lived* JWT **Authorization Token**.  
  * Anytime you are automating authentication against the DC/OS ACS API, you should use this method.  
  * Authorization tokens generated in this manner are valid for 5 days (by default)

## JWT Authorization token:
If you have a JWT authorization token, you can decode it (for example, with the tools available at jwt.io), to see its contents (be careful doing this with a token used for a production workload - this is primarily useful as a learning tool to understand what is going on).

For example, given this JWT token:
`eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.eyJ1aWQiOiJhZG1pbiIsImV4cCI6MTUyMzY0Nzg1NX0.EClzHsGZ7nwZycSA9SEGkAkA78WHpVjcqfD62to4UKDbm_HgroGorH9w8XFZPjDCV5eRAezkFhszElNPF_5_QB317c0IcnhoPUx98zXxQeFx7hY65NVbU4sTyt0_SkPLWXFiEEfZpvdsvyaJCb9-pVxK5ACXV2N1ElRMaoq7-jFtrWfkasCuBm-ijB0eqxpR_EjaAsHeTF2FMGWFCg7mF7De8KVeK2PcDQ1yH0T3h3h6U-5BN5OpAOT-YBumOn7BkRYnJV1D7r1Xf5tUgtArOP35gr-wEVzVO5ReWKht1PNb6z8J_x4a1BRYXNX1n2x1plu02FL-3IMI2a9TXNthyg`

Go to jwt.io and paste the token into the JWT decoder, you can see that the header has these contents:

```json
{
  "typ": "JWT",
  "alg": "RS256"
}
```

And the payload has these contents:

```json
{
  "uid": "admin",
  "exp": 1523647855
}
```

# Authenticating with a local user (username/password)

Basically, create a json blob with username and password, and POST it to the ACS API

```bash
# Set up env variables.  Replace with correct username, password, and master IP
export MASTER_IP=10.10.0.36
export USERNAME=admin
export PASSWORD=password

## Put username and password in a JSON file, to be passed to the DC/OS auth API
echo '{"uid": "USERNAME", "password": "PASSWORD"}' > login_request.json
sed -i "s/USERNAME/${USERNAME}/" login_request.json
sed -i "s/PASSWORD/${PASSWORD}/" login_request.json

## POST the JSON file to the auth login API
curl -k https://${MASTER_IP}/acs/api/v1/auth/login \
    -X POST \
    -H 'content-type:application/json' \
    -d @login_request.json \
    > login_token.json

## Parse the JSON response and save the token to a text file
cat login_token.json | python -c 'import sys,json;j=sys.stdin.read();print(json.loads(j))["token"]' > token
rm login_request.json
rm login_token.json

## Verify that you have an authorization token
cat token
```

# Authenticating with a service account (private/public key)

## Creating a service account
The DC/OS CLI has a handy wrapper to handle the formatting and creation of a service account.

```bash
export SERVICE_ACCOUNT=sa

# If it's not already installed
dcos package install dcos-enterprise-cli --cli --yes

# Create private key pair (using security CLI)
dcos security org service-accounts keypair ${SERVICE_ACCOUNT}-private.pem ${SERVICE_ACCOUNT}-public.pem

# Create service account (using security CLI)
dcos security org service-accounts create -p ${SERVICE_ACCOUNT}-public.pem -d "${SERVICE_ACCOUNT} service account" ${SERVICE_ACCOUNT}

# Also, add permissions to your service account - can be done either via CLI or UI
```

Alternately, you can do this with pure bash and python (to handle formatting JSON) (no DC/OS CLI).  This assumes you have already authenticated to the cluster (using the steps in `Authenticating with username/password`, above, and your token is in a file called `token`)

```bash
# Generate private / public key pair
export MASTER_IP=10.10.0.36
export SERVICE_ACCOUNT=sa

openssl genrsa -out ${SERVICE_ACCOUNT}-private.pem
openssl rsa -in ${SERVICE_ACCOUNT}-private.pem -pubout -out ${SERVICE_ACCOUNT}-public.pem

# Create JSON with proper structure for a service account
cat ${SERVICE_ACCOUNT}-public.pem | python -c 'import sys,json;k=sys.stdin.read();print(json.dumps({"public_key":k}))' > ${SERVICE_ACCOUNT}.json

# HTTP PUT it to the DC/OS ACS API
curl -kv -X PUT \
  -H "Authorization: token=$(cat token)"  \
  -H "content-type:application/json" \
  -d @${SERVICE_ACCOUNT}.json \
  ${MASTER_IP}/acs/api/v1/users/${SERVICE_ACCOUNT}
```


## Authenticating with a service account

If you have a service account set up, and have the private key (for example, one generated by the tools above), you can generate a JWT Login Token, and POST that to the ACS API to receive a JWT Authorization Token.

### Prereqs:
This requires python, with the packages `PyJWT` and `cryptography` installed.

On a DC/OS node, these are accessible automatically.  Just run `dcos-shell` to set up the proper Python environment to work in.

On a non-DC/OS node (or if you don't have direct access to the dcos-shell for whatever reason), you can run these two commands (assuming you have pip installed: `yum install python-pip` or `yum install python3-pip` (or some variant thereof, depending on your repository setup and desired python version)

Then, run one of these sets of commands:

For python2:

```bash
pip install pyjwt
pip install cryptography
```

For python3:

```bash
pip3 install pyjwt
pip3 install cryptography
```

### Generate JWT token in JSON format
This example code assumes the following:
* We want our login token to be valid for 30 seconds
* We have a service account set up with the uid `sa`
* We have a private key available as `private.pem`

**If you leave off the `exp` field in the JWT body, the JWT will be valid indefinitely.  Doing so would be considered insecure.**

*This code is intentionally verbose, as an instructional tool.  You probably should understand it and rewrite it for your specific use case.*

Python: 
```python
import time
import jwt
import json

timeout = 30
uid = "sa"
keyfile = "private.pem"
outfile = "login_token.json"

with open(keyfile, 'r') as k, open(outfile, 'w') as o:
  # Read the key from the file
  key = k.read()

  # Create a JWT login token - parameters are "payload", "private_key", and algorithm
  service_login_token = jwt.encode(
    {
      'exp': int(time.time() + timeout),
      'uid': uid
    },
    key,
    algorithm='RS256'
  ).decode('ascii')
  
  # Embed the JWT login token in JSON with additional metadata
  data = {
    'uid': uid,
    'token': service_login_token
  }

  # Write the whole data out as JSON
  o.write(json.dumps(data))
```

After running the above (in either Python2 or Python3), `login_token.json` should have contents that look like the following:

```json
{"token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE1MjMyMjAzODMsInVpZCI6InNhIn0.ELKg1InHeTJLQ4wo18JDUgipNfhTVy63UmrUIMUzk5OV0i3mD1yKltJzNJkskg7w4derx0DlJWNn8wuQ8i11O-Blsh2ajUOWTIyBEqjpwaWrLd-qISWXnfR3AZ0V9Lo43cFTAqTTelbv2EC0sAZ6G_cXgiilVjPcWnl-CzlOv1ojWA2Kh3oIIg5_bSIjd8FjHiLR7DFpLQkS9LrXIw6rQfa-Naod2X8U8LW7jPAjVZ_gKQtWEqbD34GW3cx9kSDuYAY01uyVO35em6Ue8V-y1UemPBu04r-qOkfZ_vogxOlURKDZj9k9RW_APWxUYYESGKG8mhqwdl3cFnWjtl1zRA", "uid": "sa"}
```

Note that if you decode the "token" field using jwt.io (or other JWT tools), it indicates the following payload:
```json
{
  "exp": 1523220383,
  "uid": "sa"
}
```

The `exp` field indicates how long the login token is valid; in this case, this login token is valid for 30 seconds from time of generation.

### POST JWT Login Token to DC/OS ACS API get a JWT Authorization Token

```bash
export MASTER_IP=10.10.0.36

# Get the JWT authorization token using the login token
curl -k -X POST \
  -H "content-type:application/json" \
  -d @login_token.json \
  ${MASTER_IP}//acs/api/v1/auth/login > authorization_token.json

# Extract the actual JWT token from the JSON
cat authorization_token.json | python -c 'import sys,json;j=sys.stdin.read();print(json.loads(j))["token"]' > token

cat token
eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.eyJ1aWQiOiJzYSIsImV4cCI6MTUyMzY1MjY3Nn0.vunLappuiWxa1zyFR4ESXDtFkS978O_7VwGoSreYVgjmAo4eis2ebo80uOvv548s1Wco01PyGOxFbp-NL5DgIAdj9ZB9k9G75XsE2j7wjOOGfOIlypr31IXoXhN8F4mYVDJ0vZGgujrQ5JRxsbWsEGU8EiDsBlrCF-z-Qk9me3IJ_hpCBb7SBcYNP0-ThWIxwmXlFBIc0uHG67qj8iyZHDk2y1ZEvx_haZKprwoWN6UtTMfay6lMd8tffRmvYEhtsXsZsUgNi6_Ivu8GGnKTLN2BtlC9UnF1t5DIdB7wGdGl-f5zGLbha8j5DuU6GUPIOD3ho1Ew6cCg55jVNvvqFw
```

Note that if you decode this JWT token using jwt.io (or other JWT tools), it indicates the following payload:
```json
{
  "uid": "sa",
  "exp": 1523652676
}
```

The `exp` field indicates how long the authorization token is valid; in this case, this authorization token is valid for 5 days from time of generation.