---
layout: test
---

$('.h2,h3,h4,h5,h6').filter('[id]').each(function () {
    $(this).html('<a href="#'+$(this).attr('id')+'">' + $(this).text() + '</a>');
});

<details><summary>stuff with *mark* **down**</summary><p>

## _formatted_ **heading** with [a](link)

```
{{standard 3-backtick code block omitted from here due to escaping issues}}
```

Collapsible until here.
</p></details>

Code snippet example:
{% highlight ruby lineos %}
def show
  @widget = Widget(params[:id])
  respond_to do |format|
    format.html # show.html.erb
    format.json { render json: @widget }
  end
end
{% endhighlight %}

JSON?

{% highlight json %}
{"type":"RESERVE_RESOURCES","reserve_resources":{"agent_id":{"value":"0ab83533-b525-42de-877c-a2f6ce9751f3-S2"},"resources":[{"name":"ports","type":"RANGES","ranges":{"range":[{"begin":1025,"end":2180},{"begin":2182,"end":3887},{"begin":3889,"end":5049},{"begin":5052,"end":8079},{"begin":8082,"end":8180},{"begin":8182,"end":32000}]},"reservation":{"principal":"admin"},"role":"prod"},{"name":"disk","type":"SCALAR","scalar":{"value":51042},"role":"prod","reservation":{"principal":"admin"},"disk":{"source":{"type":"MOUNT","mount":{"root":"/dcos/volume0"}}}},{"name":"disk","type":"SCALAR","role":"prod","reservation":{"principal":"admin"},"scalar":{"value":51042}},{"type":"SCALAR","name":"cpus","reservation":{"principal":"admin"},"role":"prod","scalar":{"value":4}},{"type":"SCALAR","name":"mem","reservation":{"principal":"admin"},"role":"prod","scalar":{"value":14605}}]}}
{% endhighlight %}

# DC/OS Notes, Comments, and Walkthroughs

This is an unofficial document, put together by members of the DC/OS community, to assist in the usage of DC/OS (Open Source and Enterprise Editions)

* Walkthroughs
    * [Simple Single-Master DC/OS Installation Walkthrough](walkthroughs/single-master-setup.md)
    * [Simple Multi-Master DC/OS Installation Walkthrough](walkthroughs/multi-master-setup.md)
    * [DC/OS Custom Universe](walkthroughs/custom-universe.md)


* Troubleshooting
    * [Installation FAQ](troubleshooting/installation-faq.md)


* FAQs / How Tos
    * [Frequently Asked Questions](faqs/faq.md)
    * [CPU/Memory Allocation and Utilization Guide](faqs/utilization.md)
    * [Framework Cleanup](faqs/cleanup.md)
    * [DC/OS EE Authentication API](faqs/authentication.md)
    * [DC/OS Certificates for Dummies](faqs/certificates-for-dummies.md)
    * [Simple Python Batch Jobs](faqs/simple-python-batch-jobs.md)


* Spark Stuff
    * [Spark Notes](spark/spark.md)
    * [Spark Env Setup](spark/env.md)

* Other
    * [Multi-Tenant Resource Isolation](docs/multitenant-resource-isolation.md)
    * [Migrating Masters to New IPs](docs/master-replacement.md)

