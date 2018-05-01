---
---

# Overview

This document is primarily for reference/training purposes.  A lot of the items here should not be used in production without modification.  For example, it leaves auth tokens in your command history and on your filesystem, so make sure you clean up after you're done.

This document is broken into two sections:
0. Intro to certificates (in the context of DC/OS)

1. A section regarding configuring DC/OS with certificates, including the following (**DC/OS Enterprise Only**)
    <!-- a. Using OpenSSL, creating a self-signed CA certificate and key
    b. Using OpenSSL, creating an intermediate CA, signed by the above self-signed CA certificate
    c. Configuring DC/OS EE 1.10.0 to use the intermediate CA certificate generated above -->
    a. Using the DC/OS EE CA APIs to generate and sign certificates

2. A section regarding configuring DC/OS to trust certificates, including:

    a. Create a local Docker repo using a self signed certificate

    b. Configuring the Docker daemon within DC/OS to trust certificates

    c. Configuring the UCR fetcher to trust certificates

    d. Configuring the Docker daemon with Docker creds

    e. Configuring the UCR fetcher to use Docker creds

Section 1 and 2 are only slightly related, in that:
* They both deal with certificates
* If you're running a private Docker registry, you can use the DC/OS CA to sign the certificates
* By default, the Mesos fetcher on DC/OS agents will trust certificates signed by the DC/OS CA.  
    * The Docker daemon will not trust them by default.
    * Public agents may not work correctly at the moment (this is being addressed)

There will be a follow-on document walking through configuring DC/OS Marathon-LB or Edge-LB, and 

# Intro to Certificates

This is a non-complete introduction to certificates - you can find better guides all over the Internet.  It has some very basic concepts that are helpful for understanding DC/OS behavior related to certificates.  It is also hugely simplified and leaves out symmetric keys and key negotation and a lot of other things.  A lot of the terminology is wrong.  I'm sorry.

## Relevant Concepts / Files
There are basically three files that are relevant to certificates:

* Certificates - these are generally *public* files, and are used to indicate that "I am server X".  When you connect with a server that has a certificate, the certificate is the file that is presented to the client to indicate who they are.  
    * Certificates can either be self-signed, or signed by somebody else (another trusted entity).
    * In the context of DC/OS, Enterprise DC/OS has a CA which can be used to sign certificates.  In order to fully use this functionality, your clients should be configured to trust the DC/OS CA (more on this later).
    * Certificates often have additional data embedded in them, such as owner, issuer, and lots of other metadata.
    * Certificates can indicate that they are valid for multiple entities.  For example, a server can say "I am both server X and server X.com".

* Keys - these are often sensitive files, and should be kept *private*.  They usually accompany a given certificate, but are *not* sent along with the certificate.  Generally, they are used to prove that "I'm the owner of this key".  Don't worry about the full technical details of this, aside from the fact that the key sits on the server(s) that present the certificate to clients, and is used to prove to the clients that the server is actually the owner of the certificate, but is never directly sent to the client.
    * Keys can be generated in a variety of ways.  You can use the openssl tool, or you can use DC/OS to sign certificates (if using the Enterprise version of DC/OS)
    * A certitificate is actually a public key with additional metadata.

* Certificate Signing Requests - these are an intermediate file that can be used to request a certificate, usually by somebody with a key.  Think: "Hi Verisign, I have key A, can you sign a certificate and give it to me so that I can use it to prove that I am server X"
    * EE DC/OS can process CSRs and "sign" them, and send back a certificate (more on this later).

All three file types look roughly like this, with 'XYZ' replaced with the type of content ('CERTIFICATE', 'PRIVATE KEY', or 'CERTIFICATE REQUEST' or something else), and a varying length for the body.  

```
-----BEGIN XYZ-----
MIIDVzCCAj+gAwIBAgIJANUrJ2G0RBb6MA0GCSqGSIb3DQEBCwUAMEIxCzAJBgNV
... (More lines of 64 characters) ...
qGDqzKEm14AwHwYDVR0jBBgwFoAUOPZF1A+6vegzZpBFqGDqzKEm14AwDAYDVR0T
hjCYICUonpLrQItoR+CXE+tPGCQSxjJ8SU4iGJLRL9sDKc/R/AaCoN+Cbw==
-----END XYZ-----
```

In general, this file format is called a 'PEM' file.  Also, extension doesn't always matter, but is often useful for specifying what type of pem file it is.  So you'll see things like:
* .pem used interchangeably for all
* .cert or .crt used for pem files that hold a certificate (crt often used for server certificates, cert often used for client certificates)
* .key used for pem files that hold a key
* .csr used for pem files that hold a certificate signing request

Additionally, a pem file can contain multiple pem entries concatenated together (for example, a matching certificate and key, or a list of intermediate certificates).

For this document, I will use `filename.crt.pem` to indicate a pem file holding a certificate, and `filename.key.pem` to indicate a pem file holding a key.  **This is not standard**.

## Trust

If I am a client trying to connect to server X using SSL/TLS, then all three of the following must occur:
* Server x must present a certificate that says "I am Server X", that matches the name of the server I'm trying to connect to (case insensitive)
    * If I'm trying to connect to server X.com, and the server says "I am server X", then this doesn't work.  It must be an exact match.
    * If I'm trying to connect to server A.X.com, and the server says "I am server *.X.com", then this does work (wildcard certificate)
    * If I'm trying to connect to server A.X.com, which resolves in DNS to 10.10.0.200, and the server says "I am server 10.10.0.200", then this will not work, because I'm trying to connect to the DNS name, not to the IP.  My client doesn't know that A.X.com = 10.10.0.200 (DNS resolution is outside of the client). 
    * If I'm trying to connect to server 10.10.0.200, which is the DNS resolution for A.X.com, and the server says "I am server A.X.com", then this will not work, because I'm trying to connect to the IP address, not the DNS name.  My client doesn't know that A.X.com = 10.10.0.200 (DNS resolution is outside of the client). 
* Server x must have a key that matches that certificate
    * There's some magic that goes on in the back end to handle the verification of this, that you usually don't have to worry too much about assuming you're using modern libraries.
* I must either trust the bearer certificate, or somebody else who has signed that certificate
    * I can either trust the certificate directly, or I can trust the entity that signed the certificate, or I can trust an entity that signed an intermediate certificate that was then used to sign the certificate (this is called a certificate chain, and can be relatively indefinitely long).

(Alternately, you can specify to your client not to verify trust.  This is often done with the `-k` flag in curl, or adding an exception in your browser)

## Example
If you navigate to https://gist.github.com, and inspect the certificate in your browser (different browsers have different ways of doing this), you'll see the following certificates:
* DigiCert High Assurance EV Root CA - this is inherently trusted by most computers, in your computer's trust store (all computers have a list of root CA certificates that they inherently trust)
* DigiCert SHA2 High Assurance Server CA - this certificate was signed by the Root CA (which we trust), so we trust it.
* *.github.com - this certificate was signed by the "High Assurance Server CA" (which we now trust), so we trust it.

Also, because gist.github.com matches *.github.com, we're good on the first condition.

Okay, on to actual usage in DC/OS.

# DC/OS Certificates

## Using the DC/OS EE CA APIs to generate and sign certificates

### Prereqs: 
You have must have a user with at least one of the following permissions (Reference: https://docs.mesosphere.com/1.10/security/perms-reference/)

* `dcos:superuser full` 
* `dcos:adminrouter:ops:ca:rw full`

(In this case, I've set up a user called 'ca' to achieve this task)

This also requires the tool `jq` as well as Python and curl.

In order to use the CA, or any DC/OS APIs, you must be authenticated to the DC/OS cluster.  This can be done with the DC/OS cli tool, but for the purposes of this document I'm going to use only REST APIs.

I also suggest running commands one at a time the first time you do this, because based on your shell, certain commands will hang on `rm` confirmations (`-f` is left out intentionally)

### DC/OS CA API
We're going to use the DC/OS CA to generate a private key for us, and sign a certificate that says the owner of the certificate owns a server called "repo.internal" (and the certificate will also be valid for "repo" and "10.10.0.200")

1. First, you must have a token to authenticate to DC/OS.  This set of commands will generate a token and put it in a file called token.txt

    ```bash
    export MASTER_IP=10.10.0.19
    export USERNAME=ca
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

2. Then, create a json file to request an SSH key and generate a CSR, then POST it:

    ```bash
    ## Replace with the canonical name of the server you're generating the certificate for
    export CANONICAL_NAME="repo.internal"
    ## Replace with the hostname, fqdn, and ip address of server you're generating the certificate for.
    export LIST_OF_HOSTS='"repo", "repo.internal", "10.10.0.200"' 

    echo '{
        "CN": "CANONICAL_NAME",
        "key": {"algo": "rsa", "size": 4096},
        "hosts": [LIST_OF_HOSTS]
    }' > key_request.json

    sed -i "s/CANONICAL_NAME/${CANONICAL_NAME}/" key_request.json
    sed -i "s/LIST_OF_HOSTS/${LIST_OF_HOSTS}/" key_request.json

    ## Verify the JSON looks correct
    cat key_request.json

    ## POST it
    curl -k https://${MASTER_IP}/ca/api/v2/newkey \
        -X POST \
        -H 'content-type:application/json'  \
        -d @key_request.json \
        -H "Authorization: token=$(cat token)" \
        > newkey.json

    ##### Reformat

    ## Extract the key from JSON to a single-line PEM
    cat newkey.json | python -c 'import sys,json;j=sys.stdin.read();print(json.loads(j))["result"]["private_key"]' > key.pem.oneline

    ## Convert the single-line PEM to a PEM file (may or may not be necessary)
    cat key.pem.oneline | sed 's:\\n:\n:g' > ${CANONICAL_NAME}.key

    ## Extract the CSR into a new JSON
    cat newkey.json | python -c 'import sys,json;j=sys.stdin.read();f=json.loads(j);csr={"certificate_request":f["result"]["certificate_request"]};print(json.dumps(csr))' > ${CANONICAL_NAME}.csr.json

    ## Optionally, save the CSR in PEM format
    ## cat certificate_request.pem.oneline | sed 's:\\n:\n:g' > ${HOSTNAME}.csr.pem

    ## Clean up
    rm key_request.json
    rm newkey.json
    rm key.pem.oneline
    ```


3. POST the CSR back to the API (`sign` endpoint) get the actual certificate

    ```bash
    curl -k https://${MASTER_IP}/ca/api/v2/sign \
        -X POST \
        -H 'content-type:application/json'  \
        -d @${CANONICAL_NAME}.csr.json \
        -H "Authorization: token=$(cat token)" \
        > certificate.json

    # Reformat json to PEM file (.crt)
    cat certificate.json | python -c 'import sys,json;j=sys.stdin.read();print(json.loads(j))["result"]["certificate"]' > ${CANONICAL_NAME}.crt

    # Clean up
    rm certificate.json
    rm ${CANONICAL_NAME}.csr.json
    ```

4. Remove your token

    ```bash
    rm token
    ```

Okay, so all of the above is sorta useful cause DC/OS can be used to sign certificates, which can be used in general by random servers, if you've configured your clients to trust the DC/OS CA.

# Configuring DC/OS to trust a Docker registry

In a sort of related topic, when DC/OS is starting up a container (or pod), it has to connect with your Docker registry, which has a certificate.  If you're connecting to Docker hub or some other public Docker repository, this is generally not an issue because:
* When you connect, you specify the URL for the registry (or Docker will default to index.docker.io)
* The public Docker registry will typically have a valid certificate and key matching the URL you're using (for example, *.docker.io)
* The Docker registry will have a key matching the certificate
* The certificate was signed by an entity we trust, either directly or through a certificate chain.

If you're using a custom or private registry, often the certificate will either be self signed, or signed by a non-public CA.  Then, we have to configure two things in DC/OS:
1. Configure the Docker daemon, on each of our agents, to trust the certificate.  This applies when running Docker containers with the Docker runtime (daemon)
2. Configure the Apache Mesos fetcher, on each of our agents, to trust the certificate.  This applies when running Docker containers with the Universal Container Runtime (either as containers or pods)

Key things:
* The certificate on the registry MUST match the hostname you're using to access the registry.  So if you're trying to pull 'repo.internal.lab/nginx:latest', then the certificate on the registry must match repo.internal.lab.  If the certificate instead says 'repo', then you must use 'repo/nginx:latest'.
    * The port doesn't matter.  So if you're connecting to repo.internal.lab:5000, the certificate will just say 'repo.internal.lab'
* You must be able to resolve the hostname that you're connecting to.  In the above example, you must be able to resolve 'repo' to the correct IP of the repository/registry.
* You can either directly trust the certificate on the registry, or you can trust whatever CA was used to sign the certificate.

## Configuring Docker Daemon
On each agent, you must complete the following, *for each registry*

1. Determine the url (hostname and port) used to access your registry (hostname must be part of the certificate)
2. Obtain the pem file with the direct certificate or CA certificate
3. Create a directory with this path (if using port 443, you don't need to specify port)

    ```
    /etc/docker/certs.d/<hostname>:<port>/
    ```

    For example:

    ```
    /etc/docker/certs.d/repo.internal:5000/
    ```

4. In the directory, place the certificate.  It must have an extension of .crt.  For example:
    
    ```
    /etc/docker/certs.d/repo.internal:5000/custom-ca.crt
    ```

5. Restart the docker daemon

    ```
    systemctl restart docker
    ```

## Configuring Apache Mesos Fetcher
On each agent, you must complete the following, *for each certificate* (if you have the same certificate on multiple registries, or the same CA was used to sign multiple registry certificates, this only has to be done once per certificate/CA cert)

1. Obtain the pem file with the direct certificate or CA certificate
2. Navigate to `/var/lib/dcos/pki/tls/certs` (if this directory does not yet exist, create it)
3. Place the certificate in this directory with a unique name (i.e., don't overwrite any that are already in there)
4. Run this command on the certificate to generate an 8 digit hash of the certificate: `openssl x509 -hash -noout -in <filename>`
5. Add a `.0` to the hash (i.e., if the output of the hash is 'abcd1234' then use 'abcd1234.0')
6. Create a softlink from the hash + '.0' to the file, using this command: `ln -s /var/lib/dcos/pki/tls/certs/filename.crt <hash>.0`

For example, this is the result from running this on my system:

```bash
# openssl x509 -hash -noout -in /var/lib/dcos/pki/tls/certs/custom-ca.crt 
9741086f
# ln -s /var/lib/dcos/pki/tls/certs/custom-ca.crt /var/lib/dcos/pki/tls/certs/9741086f.0
# ls -l /var/lib/dcos/pki/tls/certs/
total 8
lrwxrwxrwx. 1 root root   41 Oct 19 00:32 9741086f.0 -> /var/lib/dcos/pki/tls/certs/custom-ca.crt
-rw-r--r--. 1 root root 1220 Oct 19 00:32 custom-ca.crt
-rw-r--r--. 1 root root 1346 Oct 18 22:44 dcos-root-ca-cert.crt
lrwxrwxrwx. 1 root root   49 Oct 18 22:44 e0b903d6.0 -> /var/lib/dcos/pki/tls/certs/dcos-root-ca-cert.crt
```

(The hash will be consistent for the certificate, and only has to be generated once)


# Docker Authentication

## Docker Authentication Format
Docker authentication takes the form of a JSON file, formatted roughly like this:
```json
{
	"auths": {
		"https://index.docker.io/v1/": {
			"auth": "anVzdGlucmxlZTpmYWtlcGFzc3dvcmQK"
		
        },
        "https://local-repository.internal/v1": {
            "auth": "YWRtaW46ZGVsZXRlbWUK"
        }
	}
}
```

That is, it is the JSON equivalent of the following:
```yaml
auths:
  repository-1-url:
    auth: "<Base64 encoded 'username:password'>"
  repository-2-url:
    auth: "<Base64 encoded 'username:password'>"
```
It consists of a JSON dictionary, where the "auths" element is a dictionary of repositories to connect to.  For each repository, the key is the repository URL (including protocol and API version), and the the value is a dictionary matching `"auth":"<base64-encoded-username-pass>"`, where `<base64-encoded-username-pass>` is formatted similar to HTTP basic auth.

For example, if my username is `admin` and my password is `deleteme`, then the `auth` string can be obtained like this:

```bash
$ echo admin:deleteme | base64
YWRtaW46ZGVsZXRlbWUK
```
**Note that the auth string is not encrypted or secure in any way.**

You can also obtain this by running a Docker login, and looking at ~/.docker/config.json

## Configuring DC/OS to authenticate against a docker registry
*Much of this is taken from https://docs.mesosphere.com/1.11/deploying-services/private-docker-registry/*

Configuring DC/OS to authenticate to a Docker registry is handled differently depending on whether you're using the UCR or the Docker daemon.

Docker Daemon: One option:
* Provide a URI (http or local file on each agent) that contains a tar'd version of the ~/.docker/config.json

UCR: Three options:
* Put the Docker authentication credentials in a DC/OS secret, and reference the secret in your Marathon app definition
* Put the Docker authentication credentials in a file on the agent, and reference it with a Mesos agent environment variable when starting the Mesos agent process. (If you specify `cluster_docker_credentials` in your cluster's config.yaml, this is handled automatically for you.)
* Put the Docker authentication credentials in your config.yaml prior to cluster deployment.

## Configuring Docker Authentication for the Docker daemon

*Much of this is taken from https://docs.mesosphere.com/1.11/deploying-services/private-docker-registry/*

1. Take a given .docker/config.json (such as the one generated by running `docker login`), and tarball it up:

    ```bash
    cd ~
    tar -czf docker.tar.gz
    ```

2. Verify that it's properly formatted (must have the correct paths):

    ```bash
    tar -tvf docker.tar.gz 
    drwx------ centos/centos     0 2018-05-01 15:22 .docker/
    -rw------- centos/centos   111 2018-05-01 15:22 .docker/config.json
    ```

3. Make it available to your agent, and reference it as a fetch URI in the Marathon app definition.

    1. Option 1: Put it directly on every agent, (for example at `/var/lib/dcos/docker.tar.gz`), then reference it in a Marathon app as a URI via the `file` URI scheme:

        ```json
        {  
        "id": "/some/name/or/id",
        "cpus": 1,
        "mem": 1024,
        "instances": 1,
        "container": {
            "type": "DOCKER",
            "docker": {
            "image": "some.docker.host.com/namespace/repo"
            }
        },
        "fetch": [
            {
            "uri": "file:///var/lib/dcos/docker.tar.gz"
            }
        ]
        }
        ```

    2. Option 2: Host it on a web server available to the agent, then reference it in a Marathon app as a URI via the `http` URI scheme:

        ```json
        {  
        "id": "/some/name/or/id",
        "cpus": 1,
        "mem": 1024,
        "instances": 1,
        "container": {
            "type": "DOCKER",
            "docker": {
            "image": "some.docker.host.com/namespace/repo"
            }
        },
        "fetch": [
            {
            "uri": "http://192.168.10.30/docker.tar.gz",
            }
        ]
        }
        ```

    3. Option 3: Use one of the other URI schemes available to Marathon: https://mesosphere.github.io/marathon/docs/application-basics.html#using-resources-in-applications

## Configuring Docker Authentication for the Mesos Fetcher (Universal Container Runtime):

### Option 1: Using DC/OS Secrets

*Much of this is taken from https://docs.mesosphere.com/1.11/deploying-services/private-docker-registry/*

1. Take the .docker/config.json, and put it in a DC/OS secret (using the 'text-file' option, not the binary file-based secrets option).

    ```bash
    dcos security secrets create -f .docker/config.json /path/to/dockerconfig
    ```

    *(Make sure the secret is reachable from your Marathon app; for example, the above secret would be available to apps at `/path/to`, `/path/to/<anything>`, or `/path/to/dockerconfig/<anything>`)*

2. In your Marathon app definition, specify the secret similar to the following:

    ```json
    {
    "id": "/path/to/app",
    "container": {
        "type": "MESOS",
        "docker": {
        "image": "<image>",
        "pullConfig": {
            "secret": "pull-secret"
        },
        }
    },
    "secrets": {
        "pull-secret": {
        "source": "/path/to/dockerconfig"
        }
    }
    }
    ```

    This requires the following:
    * Designate the path to the secret with `.secret.<secretname>.source`; in the above, my application `<secretname>` is `pull-secret` and I'm referencing the secret in the Secret store at `/path/to/dockerconfig`
    * `.container.docker.pullConfig.secret`, references the application `<secretname>` (this should match the secretname indicated above - in this case, `pull-secret`)
    * `pullConfig` is case-sensitive, and should be an exact string match.

### Option 2: Specify global authentication for a given Mesos slave.

*It is **preferred** that you if you wish to use this process, you use the `config.yaml` configuration options mentioned in the DC/OS documentation, which will configure most of this for you.  If you start with a manual configuration, it may or may not be be overwritten by a DC/OS upgrade depending how you manually configure it.  This section of this document is provided more for informational purposes than anything else.*

*This should be completed on every slave that you want to run Docker images from the private repository on.*

1. On every DC/OS agent node (Mesos slave), place the Docker auth config.json somewhere on the filesystem.  For example, this may be `/var/lib/dcos/docker_credentials`, `/etc/mesosphere/docker_credentials`, `/opt/mesosphere/etc/docker_credentials`, or somewhere else.  Depending on which of these you use, this may be overwritten by DC/OS on an upgrade (the former will not be overwritten; the latter two may be overwritten)

    ```bash
    # Use only one of these:

    # Will not be overwritten on upgrade:
    cp ~/.docker/config.json /var/lib/dcos/docker_credentials

    # May be overwritten on upgrade, depending on config.yaml
    cp ~/.docker/config.json /etc/mesosphere/docker_credentials

    # Will be overwritten/erased on upgrade
    cp ~/.docker/config.json /opt/mesosphere/etc/docker_credentials
    ```

2. Add the environment variable `MESOS_DOCKER_CONFIG` to your Mesos slave process, pointing to your Docker config file.  This is most easily achieved by adding it to either `/var/lib/dcos/mesos-slave-common` or `/opt/mesosphere/etc/mesos-slave-common` (the former will persist through an upgrade; the latter will be overwritten/removed)

    ```bash
    # Use only one of these:

    # Will not be overwritten on upgrade, references /var/lib/dcos/docker_credentials
    echo 'MESOS_DOCKER_CONFIG=file:///var/lib/dcos/docker_credentials' >> /var/lib/dcos/mesos-slave-common
    # Will not be overwritten on upgrade, references /etc/mesosphere/docker_credentials
    echo 'MESOS_DOCKER_CONFIG=file:///etc/mesosphere/docker_credentials' >> /var/lib/dcos/mesos-slave-common
    # Will not be overwritten on upgrade, references /opt/mesosphere/etc/docker_credentials
    echo 'MESOS_DOCKER_CONFIG=file:///opt/mesosphere/etc/docker_credentials' >> /var/lib/dcos/mesos-slave-common

    # Will be overwritten on upgrade, references /var/lib/dcos/docker_credentials
    echo 'MESOS_DOCKER_CONFIG=file:///var/lib/dcos/docker_credentials' >> /opt/mesosphere/etc/mesos-slave-common
    # Will be overwritten on upgrade, references /etc/mesosphere/docker_credentials
    echo 'MESOS_DOCKER_CONFIG=file:///etc/mesosphere/docker_credentials' >> /opt/mesosphere/etc/mesos-slave-common
    # Will be overwritten on upgrade, references /opt/mesosphere/etc/docker_credentials
    echo 'MESOS_DOCKER_CONFIG=file:///opt/mesosphere/etc/docker_credentials' >> /opt/mesosphere/etc/mesos-slave-common
    ```

3. Restart dcos-mesos-slave

    ```bash
    systemctl restart dcos-mesos-slave
    ```

### Option 3: Specify global authentication via config.yaml

Should look something like this:

```yaml
bootstrap_url: http://192.168.10.30
cluster_name: 'dcos'
exhibitor_storage_backend: static
master_discovery: static
resolvers:
  - 8.8.8.8
  - 8.8.4.4
log_directory: /genconf/logs
security: permissive
use_proxy: 'false'
master_list:
  - 192.168.10.31
  - 192.168.10.32
  - 192.168.10.33
telemetry_enabled: false
cluster_docker_credentials:
  auths:
    'https://index.docker.io/v1/':
      auth: "anVzdGlucmxlZTpmYWtlcGFzc3dvcmQK"
cluster_docker_credentials_enabled: true
cluster_docker_credentials_dcos_owned: true
```