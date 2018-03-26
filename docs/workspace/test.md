---
---

<details><summary>stuff with *mark* **down**</summary><p>

## _formatted_ **heading** with [a](link)

```
{{standard 3-backtick code block omitted from here due to escaping issues}}
```

Collapsible until here.
</p></details>

Code snippet example:
{% highlight ruby %}
def show
  @widget = Widget(params[:id])
  respond_to do |format|
    format.html # show.html.erb
    format.json { render json: @widget }
  end
end
{% endhighlight %}