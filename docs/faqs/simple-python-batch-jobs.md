# Simple Batch Jobs

This document describes three different ways to run simple python batch jobs on a DC/OS cluster.  This is non-complete and is meant more as a simple introduction.  These are the mechanisms demonstrated:

* Using DC/OS's "Jobs" service (also known as Metronome)
* Using persistent container run in Marathon, by `exec`-ing into the container ('jump container')
* Using DC/OS's "Services" service (also known as Marathon, for long-running services, or anything that requires a capability available in Marathon but not in Metronome)

These examples all use the Docker `python:3.6` image.  Custom python images with additional Python packages could also be used.  Specifically, if you had requirements to read/write from HDFS or S3, configurations for these could be baked into a Docker image.

## Prerequisites
* A running DC/OS cluster (1.10.3 was used for this document; any DC/OS version 1.10.0 and above should work, as parts of this document rely on contaienrs run through the Universal Container Runtime)
* Permissions to run jobs and/or services on DC/OS
* Access to the cluster from some client (OSX or Linux preferred, although Windows works as well)
* Preferably, access to a customized Docker image with required Python libraries.  This document creates a dummy python image with the `requests` package
* A python script to run

### Installing and Configuring the DC/OS CLI tool (on OSX)

1. Navigate to https://github.com/dcos/dcos-cli/releases and identify the latest release (as of the time this document was updated, it was 0.5.7)
2. Right click on the binary that applies to your operating system (Darwin = OSX), and copy the link address
3. Open a new Terminal session, and cd to your Downloads directory (`cd ~/Downloads/`)
4. Download the binary using curl (`curl -LO https://downloads.dcos.io/binaries/cli/darwin/x86-64/0.5.7/dcos`)
5. Make the binary executable (`chmod +x dcos`)
6. Copy the binary to /usr/local/bin, in your executable path, using sudo (you will be prompted for your password) (`sudo cp dcos /usr/local/bin/dcos`)
7. Configure the binary to connect with your cluster, using the cluster IP address or hostname (`dcos cluster setup https://cluster-hostname/`)
    1. You will be prompted for a username and password.  If you use Google or another third party authentication mechanism, you can get the name of the provider from your administrators.
    2. If, for example, the name of your provider is `google-idp`, you may have to run the cluster setup with an additional flag (`dcos cluster setup https://cluster-hostname --provider=google-idp`)
    3. If you're using a third party authentication provider, follow the directions to obtain an authorization token and login.

### Creating a simple Docker image consisting of the 'requests' package,and host it on Docker hub

Create a file with the file 'Dockerfile' that looks like this:

`Dockerfile`

```Dockerfile
FROM python:3.6
RUN pip install requests
RUN apt-get update; apt-get install --yes vim nano emacs
```

(I've added vi, nano, and emacs, for ease of use as a jump server)

Build it (this command uses the file "Dockerfile" in the current directory, and tags the image to the default Docker hub repository at justinrlee/python-requests:3.6.  You can set up a free Docker hub account (https://hub.docker.com/); just be aware most things on a free Docker hub account are publicly available.

`docker build -t justinrlee/python:3.6-requests .`

Log in to Docker hub.

`docker login`

Push the Docker image to the Docker hub:

`docker push justinrlee/python:3.6-requests`

If you have a custom private Docker repository, you could achieve something similar with these commands:

```
docker build -t custom-repo/justinrlee/python:3.6-requests
docker push custom-repo/justinrlee/python:3.6-requests
```

### Sample job
This is a very simple dummy batch job that makes an API query to a fake REST endpoint, gets a list of users, and updates each user (note that this doesn't actually change anything).

`batch.py`, available at `https://s3.amazonaws.com/jlee-mesos/batch.py`

```python
import requests
import json

r = requests.get('https://reqres.in/api/users')
if r.status_code == 200:
  users = json.loads(r.text)['data']
  for user in users:
    print(user)
    print("Processing user {} {}...".format(user['first_name'], user['last_name']))
    requests.patch(
            url="https://reqres.in/api/users/{}".format(user['id']), 
            data=json.dumps({"processed": "yes"}))
```

## Running jobs through the "Metronome" jobs processing service
Now that we have a Docker image and a python batch script we would like to run, we can run it through the DC/OS "Jobs" service, which is also known as Metronome.

In DC/OS, a 'job' is some process that generally runs and then completes.

**Metronome jobs can be specified either through the UI or through the 'JSON MODE' json editor in the UI.  The UI does not have all available fields, so we're directly specifying properties through the JSON editor, although if you switch back out of the JSON editor when you're done you can see that fields get populated in both areas**

1. From the DC/OS UI, click on "Jobs" to get to the Metronome jobs page
2. Click on the `+` sign in the top right corner.
3. Click the "JSON MODE" toggle button in the top right corner of the popup.
4. Populate the JSON editor with this:

    ```json
    {
      "id": "test.process-users",
      "run": {
        "cpus": 1,
        "mem": 256,
        "docker": {
          "image": "justinrlee/python:3.6-requests"
        },
        "artifacts": [
          {
            "uri": "https://s3.amazonaws.com/jlee-mesos/batch.py",
            "extract": false,
            "executable": false,
            "cache": false
          }
        ],
        "cmd": "python /mnt/mesos/sandbox/batch.py"
      }
    }
    ```

    This is creating a job definition with the following properties:
    * Job name of 'process-users' in the 'test' namespace folder
    * The process can use up to 1 cpu (it will be throttled down to 1 cpu)
    * The process can use up to 256 MB of memory (if it uses more, it will be killed)
    * The job will download the Docker image `justinrlee/python:3.6-requests` and start within it
    * The job will download the batch.py file (from S3) to the directory `/mnt/mesos/sandbox` (this is the default directory).  The `uri`s in the `artifacts` fields must be reachable from the agent nodes in your cluster. (Artifact URIs cannot be configured for Metronome jobs through the DC/OS UI)
    * The job will run the command `python /mnt/mesos/sandbox/batch.py`

5. Click "Save Job"
6. Click on the "test" folder.
7. Click on your new "process-users" job
8. Click the three dots in the top right corner, and click "Run Now"

The job will start running.

In order to watch the status of your job, you can inspect it in a couple different ways:

1. Navigate to https://dcos-hostname/mesos, click on "Frameworks", then on the Framework D for the "Metronome" framework, then find the task corresponding to your job (it will either be active or completed).  From here, you can click on the "Sandbox" to get to the `/mnt/mesos/sandbox` directory within the job, and you can look at `stdout` or `stderr` for the output of your job run.

2. From the DC/OS CLI, run `dcos task --all` to identify your task (it will.  Then you can look at the logs by running `dcos task log --all <task-id>` where task-id is the value from the `ID` column.


## Running a persistent DC/OS 'jump container' service from the "Marathon" persistent tasks services, and manually running jobs from the jump container
If you have smaller/shorter batch jobs, you can start a persistent 'jump container' in the DC/OS cluster, gain shell access to it, and use it as a platform for running these jobs.

**Marathon apps (also known as "Services") are used to start long-running containers.  These containers can be used as mini jump servers from which jobs can be launched.  This is perfect for testing / running shorter jobs from a command line, so you can run the job and see output, etc.**

1. In the DC/OS UI, click on the "Services" tab to get to the Marathon services page
2. Click the `+` sign in the top right corner.
3. Click on "Single Container"
4. Specify fields as following:
    * "Service ID": "/test/jump-container-justin"
    * "Container Image": "justinrlee/python:3.6-requests"
    * "CPUs": 1
    * "Memory": 1024
    * "Command": "tail -f /dev/null"
    * "More Settings" -> "Container Runtime": "Universal Container Runtime (UCR)" or "Mesos Runtime" (depending on DC/OS version)
5. Click on "Review and Run" and then "Run Service"

The service should start up, in the 'test' directory.  This is starting and running a persistent container with the following properties:
* It is based on the `justinrlee/python:3.6-requests`
* It is allowed to use up to 1 CPU, and will be throttled down to 1 CPU if it tries to use more
* It is allowed to use up to 1024 MB of memory.  It will be killed if it tries to use more.
* In general, Docker containers have one primary process and will stop once that process has completed.  We've set the command for this container to be `tail -f /dev/null` which will essentially hang indefinitely.
* We've set the container runtime to be UCR or the Mesos Runtime, which grants you the ability to get a shell on your container without having direct access to the Linux node that it is running on.

Then, to get access to the shell, you can go to your terminal where you the DC/OS CLI configured, and use the `dcos task exec` command to `exec` into the container.

1. Exec into your container (`dcos task exec -it test_jump-container-justin bash`) (note that the slash in the service ID has been replaced with an underscore)
2. Switch to root with proper environment setup (`su -`)
3. Pull down the batch python file with wget: `wget https://s3.amazonaws.com/jlee-mesos/batch.py`
4. Run the batch python script: `python batch.py`

You can also put other scripts on the jump container and run them, using vi, nano, or emacs.

## Running a batch job in Marathon, and having it persist
If you have a batch job that requires the use of capabilities that are missing from DC/OS Jobs (such as secrets), you can run jobs from within Marathon and just have them hang when they're done.  This can also be used to run batch jobs that are designed to safely be run multiple times.

1. In the DC/OS UI, click on the "Services" tab to get to the Marathon services page
2. Click the `+` sign in the top right corner.
3. Click on "Single Container"
4. Specify fields as following:
    * "Service ID": "/test/process-users"
    * "Container Image": "justinrlee/python:3.6-requests"
    * "CPUs": 1
    * "Memory": 1024
    * "Command": "python /mnt/mesos/sandbox/batch.py; tail -f /dev/null;"
    * "More Settings" -> "Container Runtime": "Universal Container Runtime (UCR)" or "Mesos Runtime" (depending on DC/OS version)
    * "More Settings" -> "Add Artifact" -> "https://s3.amazonaws.com/jlee-mesos/batch.py"
5. Click on "Review and Run" and then "Run Service"

The service will start.  You should be able to navigate to test > process-users, and look at the actual task that is running.  If you look in the files or logs tabs, you should be able to see what's actually going on.

## More
This document was meant to give a high-level overview of this process.  Using this as a basis, here are some of the additional things you could do:
* Use other public or custom images (such as TensorFlow or custom images with credentials baked in)
* Tweak cpu/memory settings to run larger or faster jobs
* Use DC/OS secrets to store credentials
* Launch other jobs from within the cluster (using spark cluster mode)