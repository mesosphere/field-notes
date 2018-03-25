# Overview

This document details a couple different methods for authenticating with DC/OS EE, without the DC/OS cli tool.

## Authenticating with username/password

Basically, create a json blob with username and password, and POST it to the ACS API

```bash
# Set up env variables.  Replace with correct username, password, and master IP
 export MASTER_IP=10.10.0.19
 export USERNAME=username
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

 ## Verify that you have a token
 cat token
 ```

## Creating a service account
I do this with the dc/os CLI cause it's a one-time thing and can be done from an admin location, usually.

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

Alternately, you can do this with pure python (no DC/OS CLI).  This assumes you have already authenticated to the cluster (using the steps in `Authenticating with username/password`, above, and your token is in a file called `token`)

```bash
# Generate private / public key pair
export MASTER_IP=10.10.0.19
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


## Authenticating with service account

If you have a service account set up, and have the private key (generated in the example above)


### Prereqs:
This requires python, with `PyJWT` and `cryptogrpahy` installed.

On a DC/OS node, these are accessible automatically.  Just run `dcos-shell` to set up the proper Python environment to work in.

On a non-DC/OS node (or if you don't have direct access to the dcos-shell for whatever reason), you can run these two commands (assuming you have pip installed: `yum install python-pip` or `yum install python3-pip` (or some variant thereof, depending on your repository setup and desired python version))

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
You *must* replace both instances of `service-acct` with the name of your service account, (and use the right private key), before you run these.

Python2: 
```bash
cat private.pem | \
		python -c 'import sys,json,jwt;print json.dumps({"uid":"service-acct", "token":jwt.encode({"uid":"service-acct"}, sys.stdin.read(), algorithm="RS256")})' > token-request.json
```

Python3:
```bash
cat private.pem | \
		python -c 'import sys,json,jwt;token=jwt.encode({"uid":"service-acct"}, sys.stdin.read(), algorithm="RS256").decode("utf-8");print(json.dumps({"uid":"service-acct", "token":token}))' > token-request.json
```

### Submit JWT token

```bash
export MASTER_IP=10.10.0.19

curl -k -X POST \
		-H "content-type:application/json" \
		-d @token-request.json \
		${MASTER_IP}//acs/api/v1/auth/login > login_token.json

  
cat login_token.json | python -c 'import sys,json;j=sys.stdin.read();print(json.loads(j))["token"]' > token

cat token
```