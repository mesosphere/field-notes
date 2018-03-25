# Overview

This document describes how to build a Custom Universe (or Catalog) for DC/OS.  This is distinct from a DC/OS Local Universe.

High Level difference between the two:
* Local Universe allows you to access packages from the online Mesosphere Universe from a DC/OS cluster that doesn't have Internet access.  It re-hosts all artifacts as necessary.
* Custom Universe allows you to add custom packages to a DC/OS cluster.  It does not host any artifacts, and assumes they are reachable from your DC/OS cluster.

## Context: Universe

The Mesosphere "Universe" (a.k.a. Catalog in DC/OS 1.10+) acts basically as an app store for DC/OS.  

## Local Universe
Mesosphere has documention on how to deploy what's called "Local Universe" for environments where DC/OS is unable to reach the Internet (airgapped environments, proxies, etc.).

**The Local Universe allows you to run packages from the online Universe on a cluster that isn't able to reach the Internet**

A Local Universe basically operates as follows:
* It hosts a JSON file that acts as a set of application definitions, which DC/OS (the `Cosmos` service) parses and presents as installable apps
* It hosts a Docker repository, which has all of the Docker images for the specified applications
* It hosts a http repository, which hosts all of the non-Docker artifacts for the specified applications

It is built through the use of a local universe build script, which performs the following actions:
* Parses a list of desired applications
* Reads the repository json definitions of those apps and generates a list of artifacts and Docker images
* Downloads all the artifacts and Docker images
* Generates JSON repository file(s), with updated links pointing towards a hostname representing where the local universe will be hosted (such as master.mesos, if the local universe is to be hosted on your masters)
* Combines all of the items into a single Docker container, which can be run / hosted from somewhere (such as your masters)

Typically, a Local Universe is used to host packages from the online Mesosphere Universe locally (hence the name).

## New: Custom Universe

This document describes how to build a Custom Universe, which operates similarly to a Local Universe, with two changes:
* It hosts custom packages (rather than packages from the online Mesosphere Universe)
* It does not host all of the artifacts; rather, it points to artifacts hosted elsewhere (such as a local Artifactory or Docker repository which is accesible to the cluster)

**The Custom Universe allows you to add custom packages to the Universe/Catalog of a DC/OS cluster, and points to artifacts on Docker and http repositories local to the cluster**

It operates as follows:
* It hosts a JSON file that acts as a set of application definitions, which DC/OS (the `Cosmos` service) parses and presents as installable apps
* All artifact links in the definition point to local artifacts (such as on a local Artifactory Pro or Nexus server), rather than pointing back at the Custom Universe

It is built through the use of similar scripts, which performs the following actions:
* Parses a list of desired applications
* Reads the repository json definitions of those apps
* Generates JSON repository file(s) consisting of all the desired applications
* Creates a Docker container that consists of the relevant JSON repository files as well as an nginx configuration to host them so that DC/OS can interact with them.

# Building the Custom Universe

## Setup
You will need a server on which to build your Custom Universe.  I'm using a CentOS 7.3 box with Docker 1.13.1 already installed.

You'll also need git and python3:

```bash
yum install -y git
```

```bash
yum install -y epel-release
yum install -y python34

```

We're going to clone the mesosphere/universe repository, and then copy select parts of it over to a new folder.

```bash
git clone https://github.com/mesosphere/universe.git
mkdir custom-universe
mkdir -p custom-universe/scripts
mkdir -p custom-universe/repo/packages
mkdir -p custom-universe/docker/server
cp -rpv universe/scripts/* custom-universe/scripts/
cp -rpv universe/repo/meta custom-universe/repo/
cp -rpv universe/docker/server/* custom-universe/docker/server/
```

## Create packages

Now, we will put all the packages we want in our Custom Universe in `custom-universe/repo/`.  First, a little bit about the structure of packages:

### Package Structure

All package definitions must be formatted per the package definitions as defined at https://github.com/mesosphere/universe#creating-a-package (for the purpose of this doc, I'm using the 3.0 version of the package schema)

Basically, a package consists of 3 json files, and a mustache file.

* **package.jso**n: defines high level metadata about the package, such as package name and version, and what versions of DC/OS it's compatible with.
* **resource.json**: defines all of the externally hosted resources (Docker images, HTTP objects, and images) used for the package
* **config.json**: defines all of the configurable options for a given package
* **marathon.json.mustache**: a [mustache](https://en.wikipedia.org/wiki/Mustache_(template_system)) template that, when combined with the three JSON files, generates a Marathon JSON app definition that gets fed into Marathon.

These four files should be placed in a directory structure like this: `custom-universe/repo/<First-Capital-Letter>/<Package-Name>/<Package-Iteration>`

(package iteration is not the same as package version)

For example, if we're going to build a package called "custom-package", and this is our first time doing this, we'd place our files in:

`custom-universe/repo/packages/C/custom-package/0/`

If we wanted to create a new version of custom-package, we'd place it in:

`custom-universe/repo/packages/C/custom-package/1/`

Then, we'd have multiple versions of our package available to our DC/OS cluster.  *Only the latest iteration of the package will show up in the UI, but previous versions would be installable via the CLI.*

You can generate a package definition in a couple different ways: you can copy and modify an existing package definition, or you can start from scratch.  For the purposes of this doc, I'm going to copy and modify the Jenkins package definition to point to a custom Jenkins image, and rename the package to "Custom-Jenkins"

### Custom-Jenkins
First, copy the latest iteration of the Mesosphere `jenkins` package to our custom universe repository, in the correct path for the first iteration of a package called `custom-jenkins`:

```
mkdir -p custom-universe/repo/packages/C/custom-jenkins/0/
cp -rpv universe/repo/packages/J/jenkins/23/* custom-universe/repo/packages/C/custom-jenkins/0/
```

Let's go into that directory (`cd custom-universe/repo/packages/C/custom-jenkins/0`), and make changes to the files accordingly:

#### `package.json`
Old `package.json`:
```json
{
  "packagingVersion": "3.0",
  "name": "jenkins",
  "version": "3.3.0-2.73.1",
  "minDcosReleaseVersion": "1.8",
  "scm": "https://github.com/mesosphere/dcos-jenkins-service.git",
  "maintainer": "support@mesosphere.io",
  "website": "https://jenkins.io",
  "framework": true,
  "description": "Jenkins is an award-winning, cross-platform, continuous integration and continuous delivery application that increases your productivity. Use Jenkins to build and test your software projects continuously making it easier for developers to integrate changes to the project, and making it easier for users to obtain a fresh build. It also allows you to continuously deliver your software by providing powerful ways to define your build pipelines and integrating with a large number of testing and deployment technologies.",
  "tags": ["continuous-integration", "ci", "jenkins"],
  "preInstallNotes": "WARNING: If you didn't provide a value for `storage.host-volume` (either using the CLI or via the Advanced Install dialog),\nYOUR DATA WILL NOT BE SAVED IN ANY WAY.\n",
  "postInstallNotes": "Jenkins has been installed.",
  "postUninstallNotes": "Jenkins has been uninstalled. Note that any data persisted to a NFS share still exists and will need to be manually removed.",
  "licenses": [
    {
      "name": "Apache License Version 2.0",
      "url": "https://github.com/mesosphere/dcos-jenkins-service/blob/master/LICENSE"
    }
  ],
  "selected": true
}
```

Let's change the name, version, maintainer, description, and pre and post installation notes.

*By convention ,versions are [package-version]-[application-version].  So in this case, first version of this package, and Jenkins 2.73.1.*

New `package.json`:
```json
{
  "packagingVersion": "3.0",
  "name": "custom-jenkins",
  "version": "1.0.0-2.73.1",
  "minDcosReleaseVersion": "1.8",
  "scm": "https://github.com/mesosphere/dcos-jenkins-service.git",
  "maintainer": "jlee@mesosphere.com",
  "website": "https://jenkins.io",
  "framework": true,
  "description": "This is a modified version of the Jenkins package.",
  "tags": ["continuous-integration", "ci", "jenkins"],
  "preInstallNotes": "WARNING: If you didn't provide a value for `storage.host-volume` (either using the CLI or via the Advanced Install dialog),\nYOUR DATA WILL NOT BE SAVED IN ANY WAY.\n",
  "postInstallNotes": "Custom Jenkins has been installed.",
  "postUninstallNotes": "Custom Jenkins has been uninstalled. Note that any data persisted to a NFS share still exists and will need to be manually removed.",
  "licenses": [
    {
      "name": "Apache License Version 2.0",
      "url": "https://github.com/mesosphere/dcos-jenkins-service/blob/master/LICENSE"
    }
  ],
  "selected": true
}
```

*Note: `"selected": true` is what determines whether a package shows up in the "Certified" section of your Universe/Catalog.  Change this according to whether you want your new package to show up there or not.*

#### `config.json`

For `config.json`, we're only going to change two things:
* Change the default name from "jenkins" to "custom-jenkins"
* Change the default memory from 2048.0 MB to 3072.0 MB

Rather than displaying the whole file, I'm just going to sed it:

```
sed -i 's/"default": "jenkins"/"default": "custom-jenkins"/' config.json
sed -i 's/"default": 2048.0/"default": 3072.0/' config.json
```

#### `resource.json`
For `resource.json`, I've just retagged `mesosphere/jenkins:3.3.0-2.73.1` to `justinrlee/custom-jenkins:2.73.1` on Docker hub, so we make the change to `resource.json`:

Old `resource.json`:
```json
{
  "images": {
    "icon-small": "https://downloads.mesosphere.com/universe/assets/icon-service-jenkins-small.png",
    "icon-medium": "https://downloads.mesosphere.com/universe/assets/icon-service-jenkins-medium.png",
    "icon-large": "https://downloads.mesosphere.com/universe/assets/icon-service-jenkins-large.png"
  },
  "assets": {
    "container": {
      "docker": {
        "jenkins-330-2731": "mesosphere/jenkins:3.3.0-2.73.1"
      }
    }
  }
}
```

New `resource.json`:
```json
{
  "images": {
    "icon-small": "https://downloads.mesosphere.com/universe/assets/icon-service-jenkins-small.png",
    "icon-medium": "https://downloads.mesosphere.com/universe/assets/icon-service-jenkins-medium.png",
    "icon-large": "https://downloads.mesosphere.com/universe/assets/icon-service-jenkins-large.png"
  },
  "assets": {
    "container": {
      "docker": {
        "jenkins-330-2731": "justinrlee/custom-jenkins:2.73.1"
      }
    }
  }
}
```

*You could optionally point this to a local Docker repository rather than Docker hub (for example, `local-repo.customer.lab/custom-jenkins:2.73.1`).  If you do this, make sure you follow the steps in the [certificate guide](../faqs/certificates-for-dummies.md) to configure your agents to trust your local Docker repository, otherwise you'll run into certificate errors when you actually try to install the package.*

#### `marathon.json.mustache`
The `marathon.json.mustache` file is basically the pre-rendered version of your Marathon app definition.  Mustache is used to plug in values from `config.json` and `package.json`.  I'm not making any changes in this guide, but if you desire changes to your Marathon app definition you could do so here.

## Build the repository JSON files
The scripts we're using are based in the scripts directory, but must be executed from the root of the custom-universe directory tree (in my case, `~/custom-universe`)

```bash
cd ~/custom-universe
```

Then, run the build script:

```bash
bash scripts/build.sh
```

If you look in the `target` directory, you'll see a handful of files that get created.  These are all served by the Custom Universe; based on which version of DC/OS is accessing the Custom Universe, nginx will serve the correct json file.

```bash
[root@ip-10-10-0-80 custom-universe]# ls -alh target/
total 100K
drwxr-xr-x. 2 root root 4.0K Nov 30 01:54 .
drwxr-xr-x. 5 root root   44 Nov 30 01:20 ..
-rw-r--r--. 1 root root   64 Nov 30 01:54 repo-empty-v3.content_type
-rw-r--r--. 1 root root   16 Nov 30 01:54 repo-empty-v3.json
-rw-r--r--. 1 root root   64 Nov 30 01:54 repo-up-to-1.10.content_type
-rw-r--r--. 1 root root  11K Nov 30 01:54 repo-up-to-1.10.json
-rw-r--r--. 1 root root   64 Nov 30 01:54 repo-up-to-1.11.content_type
-rw-r--r--. 1 root root  11K Nov 30 01:54 repo-up-to-1.11.json
-rw-------. 1 root root  784 Nov 30 01:54 repo-up-to-1.6.1.zip
-rw-------. 1 root root  784 Nov 30 01:54 repo-up-to-1.7.zip
-rw-r--r--. 1 root root   64 Nov 30 01:54 repo-up-to-1.8.content_type
-rw-r--r--. 1 root root  11K Nov 30 01:54 repo-up-to-1.8.json
-rw-r--r--. 1 root root   64 Nov 30 01:54 repo-up-to-1.9.content_type
-rw-r--r--. 1 root root  11K Nov 30 01:54 repo-up-to-1.9.json
-rw-r--r--. 1 root root   64 Nov 30 01:54 universe.content_type
-rw-r--r--. 1 root root  11K Nov 30 01:54 universe.json
```

## Build the Custom Universe
First, copy the `target` directory to the `docker/server` directory (run from the custom-universe directory):

```bash
cp -rpv target docker/server/
```

Then, cd into the `docker/server` directory, and run a Docker build (replace with whatever Docker image/tag you would like):

```bash
cd docker/server
docker build -t justinrlee/custom-universe .
```

You will end up with a Docker image that can be run anywhere to your DC/OS cluster, and added as a repository link:

```bash
[root@ip-10-10-0-80 server]# docker images
REPOSITORY                   TAG                 IMAGE ID            CREATED             SIZE
justinrlee/custom-universe   latest              8852c6d02ab8        6 minutes ago       60.7 MB
```

# Running and Using the Custom Universe
This Docker image is basically a nginx-based Docker image that you can point a DC/OS cluster at.  It can be run in a variety of ways, on any desired static static port, as long as your DC/OS cluster can reach it.

By default it listens on port 80 (also 443, but 443 doesn't do anything as it's currently configured).

For example, if I wanted to run this on some utility server on port 8080, I would do the following:

```bash
docker run -d -p 8080:80 justinrlee/custom-universe
```

Then, I could verify that it's reachable:

```bash
curl utility-server:8080/universe.json
```

Then, through the DC/OS CLI (or UI), I could add my local universe as a repository (use the `/repo` path, and it will redirect accordingly):

```bash
dcos package repo add Custom-Universe http://utility-server:8080/repo
```

Then, if you go to your Universe / Catalog, your new packages should show up.