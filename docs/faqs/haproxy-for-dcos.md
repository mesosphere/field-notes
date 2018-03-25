# Overview: DC/OS Ingress Load Balancers: Marathon-LB and Edge-LB
When you're working with a container orchestration tool such as DC/OS, one vitally important capability and requirement that you should keep in mind is the mechanism you're going to use to expose your microservices (which often live in semi-ephemeral locations on semi-random ports) to your end users.  DC/OS provides two† main ways to achieve this: Marathon-LB and Edge-LB (EE only).

Both of these tools essentially boil down to one core piece of software: HAProxy, with add-on bits to automagically generate the HAProxy configuration file.  Specifically, at a very high level:

* Marathon-LB uses the Marathon event bus to look at all of the Marathon services running in your cluster.  Then, based on Marathon labels (of the form HAPROXY_{n}_TEMPLATE) attached to your applications and information (IPs and ports) about the application instances, it will generate an HAPRoxy configuration, and update itself to the new HAProxy configuration.  
    * It is composed of a Docker container that runs both a python script to generate the haproxy.cfg file, and the haproxy instance itself.
    * Of note: Marathon-LB uses the concept of self registration - each Marathon service basically is able to registry with Marathon-LB by adding the appropriate labels.  There is no central configuration of Marathon-LB, which can be either a positive or negative thing, depending on your use case.
    * As of now, Marathon-LB only supports Marathon apps (no pods and no non-Marathon services, although there are some ways around some of these limitations)
* Edge-LB, which is currently for DC/OS Enterprise users only, looks at various Apache Mesos APIs to determine where all of your services and applications are running.
    * It is composed of three components:
        * An API server, with a wrapping CLI that can be used to submit configurations and handles generation of the haproxy configuration
        * A pool service dcos-commons framework service, which is used to control the HAProxy instances
        * The HAProxy instances themselves
    * Of note, Edge-LB is centrally managed - it is primarily configured through a YAML (or equivalent JSON) file which details the high-level configurations for your load balancers.  Again, this can be positive or negative - it may require more maintenance from an administrative perspective but also grants much more control
    * Edge-LB supports pods and non-Marathon services.  It is much more flexible.

*†This document discusses ingress into your cluster for end users; it does not discuss the service link provided by the DC/OS adminrouter, which is technically a third mechanism.  It also doesn't discuss CNI routing or any of the other related options.*

*†This document is not meant to be super technical.  *

Both of these load balancers are based off of HAProxy, so let's start with an introduction to HAProxy

# Introduction to HAProxy
