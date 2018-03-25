# What is a DC/OS Framework (and why do I care)?



This is a basic (hugely simplified) explanation of how many DC/OS services operate.

*'Framework' and 'Scheduler' are used relatively interchangeably in this document*

In a DC/OS cluster, you have three components relevant to this discussion:

* DC/OS masters, which run the Apache Mesos Master component (dcos-mesos-master)
* DC/OS agents, which run Apache Mesos Agent components (dcos-mesos-slave or dcos-mesos-slave-public)
* Framework processes, which are processes that register with the Apache Mesos master as Apache Mesos Frameworks

A brand new DC/OS cluster starts with some odd number of masters, some number of agents, and two framework processes, both of which run on all of master nodes:

* Marathon
* Metronome

*For the purposes of this dicussion, we're going to ignore Metronome*

Marathon is what's called an "Apache Mesos Framework", which means that it's registered with Apache Mesos as a framework scheduler to tell the Apache Mesos cluster to run 'tasks' (which essentially end up as some form of containerized processes)

For example, Marathon is registered with the Mesos master cluster as a framework.  This means that it can tell Mesos to run several instances of the `nginx` Docker image.  Then, the Mesos masters will trigger various Mesos slaves to start up instances according to Marathon's specifications.

*This is hugely simplified; there's a variety of API calls and negotations that take place to determine whether the tasks are allowed to run, where they're allowed to run, etc.*

Because Marathon can essentially run any form of task or process on the Mesos cluster, it can run processes that will then register directly with Mesos as new frameworks.  The Elastic framework is an example of this; when you spin up the Elastic framework in Marathon, what you're actually doing is starting a process (through Marathon) that registers as a Mesos framework.  The Elastic framework is then able to directly tell Mesos to start its own child tasks.

**These tasks have no correlation with Marathon, aside from the fact that their parent framework is running as a Marathon task.**

So when you kill a Marathon task (such as by clicking the `Destroy` button), you're killing the Framework task (running in Marathon) that created the children tasks, but you're not actually killing the children tasks.