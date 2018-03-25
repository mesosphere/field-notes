# Framework Cleanup

When a framework (such as Spark / Elastic) is removed from DC/OS by clicking the `Destroy` button in the DC/OS Services UI, it tends to leave a lot of stuff hanging around in DC/OS.  You may notice that if you destroy a service and re-create it, it will either (a) have stuff left over from previous deployments or (b) will refuse to properly start up.

The root cause of this is this: a DC/OS services may be started as a Marathon task (which is stopped/started by the Marathon framework), but that task may then register directly with Apache Mesos as a new framework (independent of Marathon).  Because the task is now an Apache framework, it can trigger the start of new Apache Mesos tasks.

Here's the key point:

**Clicking the `Destroy` button in the DC/OS UI will kill the framework task, but will not kill tasks that were started by that framework task.**

In addition to potentially leaving the tasks running, there may be other pieces of the frameworks left over after a service is 'destroyed' (i.e., the master framework task is killed).

* Some of the frameworks store data in zookeeper, which is the distributed datastore used by DC/OS.  Destroying the framework task does not remove the data.
* The frameworks may have created resource reservations in Apache Mesos.  Destroying the framework task does not free up these resource reservations.

There are two ways to completely remove a service:
* The documented process (remove via CLI, run Janitor)
* The undocumented way (remove via UI, tear down the framework, run Janitor)

### Documented Process: Remove via CLI, run Janitor

If you look at the documentation for the major frameworks, they all have a documented uninstall process.  This follows roughly these steps:

1. Remove the framework through a `dcos uninstall --app-id=<service-name> <service>` command

2. Cleaning up the framework through the use of the janitor script.

Because this process is relatively well documented (just see the documentation for your service of choice), I'm not going to elaborate further here.

### Undocumented process: Remove via "Destroy" button, tear down the framework manually, run Janitor

Usually users get to this point by clicking "Destroy" on a service in the DC/OS UI rather than running the uninstall command.  This doesn't properly clean up after the removed service.

Here's how to fix this:

1. Load up the Mesos UI (reachable via https://\<master-url\>/mesos/), and click on the "Frameworks" tab
2. Identify your destroyed framework.  It will have a 
If, however, you've done 'destroyed' it in the UI, then it will be in a inactive but incomplete state.  This is because you will have killed the framework without killing its children tasks.  If you get to this point, you can identify the framework id by looking in the mesos UI, and then tear down all the children tasks with this:

> curl -v -X POST http://hostname:5050/teardown -d 'frameworkId=\<frameworkId\>'

For example:

```
curl -v -X POST leader.mesos:5050/teardown -d 'frameworkId=4f657f09-c73f-408f-8d9e-37228a0f1a8e-0003'
```

Step 2:
The janitor script is documented here: https://docs.mesosphere.com/1.9/deploying-services/uninstall/#framework-cleaner

The official way to do this is from a Docker container which has all of the dependencies.  However, due to your environment, it may be significantly easier to just run it as a python3 script.  You have to set up some environment stuff.

Also, the easiest way to do this is to run it from a master.

In DC/OS 1.8.x: (I tested this in 1.8.8, have not tested it in 1.8.5; I believe it should be roughly the same, but if you have issues, let me know:

source /opt/mesosphere/environment
/opt/mesosphere/bin/python3 janitor.py <options>

In DC/OS 1.9.0
dcos-shell # To start a 'dcos shell' which has all the env stuff
/opt/mesosphere/bin/python3 janitor.py <options>

The options you need should look something like this:

-r <role> -p <principal> -z <zookeeper-path>

So you'd run it something like this:

<whichever env setup you need>
/opt/mesosphere/bin/python3 janitor.py -r kafka-role -p kafka-principal -z dcos-service-kafka

And here's the janitor.py script: