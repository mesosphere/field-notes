# DC/OS Multi-tenant Resource Isolation in DC/OS 1.10 and 1.11

## Purpose
This document details various options available in DC/OS 1.10.x and 1.11.x to support isolating multiple tenant's workloads on a single DC/OS cluster.
Note that the general theme of the 1.12 is "Multi-tenancy", so all of this is subject to change  in 1.12.  More specifically, many new options regarding this topic may become available.

## Background

### Apache Mesos

DC/OS is meant to be a single operating system for a large, multi-node cluster.  It's built aroun the open source project **Apache Mesos**, which acts as the kernel of the cluster.

* Apache Mesos allows the allocation of resources to multiple **Frameworks**, each of which is a separate entity that is allowed to consume resources on the cluster.

* Frameworks will **register** with the Apache Mesos cluster (via **Mesos masters**), and request the use of resources on the cluster.

* When a framework registered with Apache Mesos, it will indicate what **Role** it is registering (for example, the `prod` or `dev` role).

* Resources in a cluster are by default available to any role (i.e., all resources are "available" for the `*` role, which is "any role").

* Resources can be reserved for specific roles (this is discussed later, in the **_Reservations and Quotas_** section).

* Apache Mesos will attempt to allocate resources (CPU, memory, disk, etc.) in a fair manner among all the frameworks that have registered with it and requested resources.  *(A whitepaper describing the allocation algorithm can be found by searching for `Dominant Resource Fairness: Fair Allocation of Multiple Resource Types`).*

* This works on the concept of an **offer cycle**: Mesos is aware of (1) what frameworks are present, (2) how many resources they're each utilizing, and (3) whether they're still asking for more resources, and based on these datapoints, will submit **resource offers** to frameworks indicating that the frameworks can utilize the offered resources on the cluster.

* Frameworks, once they receive the resource offers, can **accept** or **reject** the resource offers, and tell the cluster what process(es) they would like to run on the offered resources.

### DC/OS Core Framework

A standard installation of DC/OS comes with two built-in frameworks, which register with the Apache Mesos cluster that is the central components of the DC/OS cluster.

* **Marathon**, which is used to run long-running jobs.  This shows up in the DC/OS UI as the **Services** tab.  The default Marathon instance uses the `slave_public` role.  This will be referred to as the **root Marathon** for the duration of this document.

* **Metronome**, which is used to run batch-style ad-hoc or scheduled jobs.  This shows up in the DC/OS UI as the **Jobs** tab.

### DC/OS Catalog Frameworks (SDK Services)

In addition the core (root) Marathon and Metronome services, certain packages from the DC/OS **Catalog** will install additional frameworks.  For example:

* **Kafka**, when installed from the Catalog, will start a framework that will request resources from the Apache Mesos cluster with which to run Kafka Brokers
* **Cassandra**, when installed from the Catalog, will start a framework that will request resources from the Apache Mesos cluster with which to run Cassandra Nodes
* *and so on...*

Many of these services were built by a common framework building mechanism, called the **DC/OS Service SDK** or **DC/OS Commons**.  For the remainder of this document, these will be referred to as **SDK services**.

Of note, while these frameworks will register with Apache Mesos and request resources with a given role (for example, `kafka-role`), the actual process that the framework itself is running on is run as a Marathon service.  So you have this high-level architecture:

* Marathon is registered with Mesos as a framework (`marathon`), and is using resources with the `slave-public` role to run the `kafka` Marathon service as children tasks of the `marathon` framework.
* The `kafka` service, which is itself running within Marathon (as a child task of Marathon), will additionally register with Mesos as a separate framework (`kafka`).  This will spin up brokers using the `kafka-role` role, which are children tasks of the `kafka` framework.
* Mesos is running a process `kafka` under Marathon using resources allocated to the `slave_public` role.  Marathon is not inherently aware of what this process is doing (or that it is a framework); as far as Marathon knows, this is just a generic Linux binary.
* Mesos is separately running multiple kafka `broker` processes under Kafka using resources allocated to the `kafka-role` role.

### DC/OS Frameworks: Core + Catalog

So, when you have a DC/OS cluster and have installed several SDK services (such as Kafka and/or Elastic), you end up with a handful of Mesos frameworks, all competing for resources.  Mesos will try to allocate resources approximately fairly to all of the framework.

Once the SDK services have all of the resources they need, they'll tell the Mesos cluster that they don't need any more resources, and the remainder of resources will be allocated to any frameworks still asking for resources.

Once all of the SDK services are complete, Mesos will continue to send resources to the remaining frameworks that are requesting offers.  For the purposes of this document, this is primarily Marathon.

### The Issue

By default, there is only one Marathon running on a DC/OS cluster; all users of the cluster are able to submit whatever applications and services they would like to Marathon to run, and a given Marathon instance has no inherent prioritization of resources among its users.

Any user who has access to the core Marathon can therefore submit marathon app manifests, and Marathon will tell Mesos it's looking for resources, and Mesos will essentially give Marathon all of its available resources.

This leads to a lack of granularity and segmentation of the cluster.  You can specify **Mesos attributes** on specific nodes, and attribute **constraints** on individual Marathon apps, such that the only place Marathon will place instances of those apps is on nodes that meet the given constraints, but this will not prevent Marathon from placing unconstrained apps on those nodes.

For example, if a cluster the following:

* A set of expensive bare-metal nodes, with attribute `type:baremetal`
* A set of inexpensive virtual machine nodes, with attribute `type:vm`

Then we could specify that app `/baremetal-app` must always run on a baremetal node, but there's no (simple) way to reserve the expensive baremetal for only a certain class of apps with the core Marathon, or the ensure that other applications or users stay on the virtual machine nodes.

## Resource Isolation - Multiple Frameworks

So how do we ensure that certain workloads (for example, prod), are guaranteed a certain set of resources?  At a high level, there are a couple tools we can combine to achieve this:

* Split workloads onto multiple frameworks.  This is achieved by starting additional Marathon instances (in DC/OS parlance, this is known as "Marathon on Marathon", because the actual framework process runs as a child task of the root Marathon.

* Split up the resources on the cluster, and allocate them to the roles associated with the different framework.  There are several mechanism to achieve this, discussed below.

### Marathon-on-Marathon (MoM)

You can spin up additional Marathon frameworks, and have the actual framework process run on the root Marathon.  This is called "Marathon-on-Marathon", or **MoM**.

In the DC/OS Catalog, there is a package called "Marathon"; this can be used to install an OSS MoM.  While starting up an OSS MoM, make sure to customize the following settings:

* `service.name`: Should be changed to something describing the Marathon instance.  For example, `marathon-prod`
* `marathon.default-accepted-resource-roles`: This indicates the type of role offers that the Marathon instance should accept by default.  For example, you could specify `prod` to **only** accept resources reserved for the `prod` role.  Alternately, you could specify `*,prod` to configure the MoM to accept both resource offers that are flagged as reserved for `prod` or offers that are unreserved (configured with the role `*`).  The choice here will depend priority of the workload type, and the configuration of your cluster resources.
* `marathon.mesos-role`: This is the resource role you want your MoM to use.  In this example, you would specify `prod`.

One MoM is up and running, you can access the Marathon interface by clicking on the "Open Service" link next to the service, or by navigating to `https://<dcos-url>/services/marathon-prod`.

In addition to the OSS MoM, DC/OS users who have an enterprise license with Mesosphere can use the Enterprise Edition of Marathon-on-Marathon, which adds the following capabilities:
* Support for DC/OS EE Strict Mode
* Support for DC/OS Secrets
* Support for DC/OS ACL Control

#### Configuring Access to MoM

* WIP

### Splitting up Cluster Resources
There are several options available to us now (in DC/OS 1.10.x and 1.11.x, which correspond to Apache Mesos 1.4.x and 1.5.x, respectively):

* **Static Reservations**: Resources on a given cluster node can be hard-coded to be reserved for a given role.  Changing this requires essentially wiping the node.
    * For example, on a given bare-metal node, we could hard-code that all of its resources are reserved for `prod` workloads.

* **Dynamic Reservations**: Resources on a given cluster node can, during runtime, be configured to be reserved for a given role.  Changing this is achieved by the Mesos Operator API.
    * For example, if we know that we have some large `prod` workload coming up that will require a specific type of resources, we could dynamically reserve resources on a set of certain nodes to be reserved for `prod` workloads.
    * Alternately, we could use the dynamic reservation operator API to reserve a set of resources on a given node on an essentially persistent basis.

* **Quotas**: A set of resources cluster-wide can be reserved for a given role.  
    * For example, assume we have 20 nodes, each with 10 CPU cores and 256 GB of memory (200 cores and 5 TB of memory).  If we want to ensure that `prod` workloads are not affected by other workloads (such as `dev` or `test`), we could set a 'quota' of 100 cores and 2560 GB of memory for the `prod` role.
    * *Of note: a quota is also currently a limit; if you set a quota of 100 cores and 2560 GB of memory for a given role, that role will be guaranteed that amount of resources, but it will also **only** be allowed to use that amount of resources.*

### Currently Unsupported Features

* WIP

#### Quota Minimums and Maximums
#### Hierarchical Roles
#### Hierarchical Quotas
#### Multi-role reservations
#### Revocable Reservation

## Spark

* WIP

## Load Balancing / Ingress

* WIP

### Marathon-LB

* WIP

### Edge-LB

* WIP

## Example: MoM + Dynamic Reservations + Quotas + Edge-LB

* WIP