# What is the difference between browser now() and server now()?
browser_server_time_offset = 0
correct_date = (date) ->
  time = if date.getTime? then date.getTime() else date
  time += browser_server_time_offset
  return new Date(time)

class Router extends Backbone.Router


class ProgTime extends Backbone.Model
  initialize: (socket) ->
    @socket = socket
    super()
  send_stop: =>
  send_start: =>
  send_update: =>
  receive_update: (data) =>

# View for a simple clock displaying the current time.
class ClockView extends Backbone.View
  render: =>
    go = =>
      @$el.html(
        # Remove seconds
        new Date().toLocaleTimeString().replace(/\d+:\d+(:\d+)/, "")
      )
    clearInterval(@goer) if @goer?
    @goer = setInterval go, 1000
    this
  remove: =>
    clearInterval @goer if @goer?
    super()
    
# View for the button with built-in category timer.
class CategoryView extends Backbone.View
  template: _.template $("#showCategory").html()
  events:
    'mousedown a.activate': 'mouseToggleActive'
    'touchstart a.activate': 'touchToggleActive'

  initialize: (model, category) ->
    @model = model
    @category = category
    @active = false

  remove: =>
    @model.off null, null, this
    super()

  mouseToggleActive: (event) =>
    event.preventDefault()
    unless @touchIsEnabled
      @toggleActive()

  touchToggleActive: (event) =>
    event.preventDefault()
    @touchIsEnabled = true
    @toggleActive()

  toggleActive: (event) =>
    if @active
      @active.stop = new Date()
      @active = false
      @render()
      @model.send_stop()
    else
      @active = {
        start: new Date()
        stop: null
      }
      @model.get("categories")[@category].push(@active)
      @model.send_start()
      @render()

  get_elapsed_and_set_active: =>
    elapsed = 0
    for time in @model.get("categories")[@category]
      if time.category == @category
        start = new Date(time.start)
        if time.stop
          stop = new Date(time.stop)
          @active = null
        else
          stop = correct_date(new Date())
          @active = time
        elapsed += stop.getTime() - start.getTime()
    seconds = Math.round(elapsed / 1000) % 60
    seconds = if seconds < 10 then "0" + seconds else seconds
    minutes = Math.floor(elapsed / 1000 / 60)
    return "#{minutes}:#{seconds}"

  render: =>
    @$el.addClass("buttonrow")
    elapsed = @get_elapsed_and_set_active()
    @$el.html @template {
      category: @model.get('categories')[@category] or "Undefined"
      elapsed: elapsed
      active: @active
    }

class Settings extends Backbone.View
  template: _.template $("#settings").html()
  max_num_categories: 8
  events:
    'click a.save': 'save'
    'click .cancel': 'cancel'

  initialize: (model) ->
    @model = model

  render: =>
    @$el.html @template {
      model: @model.toJSON()
      max_num_categories: max_num_categories
    }

  save: =>
    names = (@$("input.cat-#{i}").val() for i in [0...max_num_categories])
    cats = @model.get("categories")
    for name,i in names
      if i >= cats.length and name
        # Add new names if they are non-empty
        cats.push {name: name}
      else if i < cats.length
        # Tolerate non-empty names for existing categories to trigger deletion
        cats[i].name = name

    @model.set({ name: @$("input.name") })
    @model.send_update()
    @trigger "done"

  cancel: =>
    @trigger "done"

class TimeKeeper extends Backbone.View
  template: _.template $("#timekeeper").html()
  events:
    'click .settings': 'settings'
    'click .graph': 'graph'
    'click .reset': 'reset'

  initialize: (model) ->
    @model = model
    @model.on "change", @render, this

  remove: =>
    @model.off null, null, this
    super()

  settings: (event) =>
    event.preventDefault()
    app.navigate("settings", {trigger: true})

  graph: (event) =>
    event.preventDefault()
    app.navigate("graph", {trigger: true})

  reset: (event) =>
    event.preventDefault()

  render: =>
    @$el.html @template {
      model: @model.toJSON()
    }
    for view in @catviews or []
      view.remove()
    @catviews = []
    for cat,i in @model.get("categories")
      if cat.name
        catview = new CategoryView(model, i)
        @$(".categorylist").append(catview.el)
        catview.render()
        @catviews.push(catview)
    
    min = Number.MAX_VALUE
    for cat in @model.get("categories")
      if cat.times.length > 0
        min = Math.min(min, cat.times[0].start)
    if min < Number.MAX_VALUE
      @$(".meeting-start").html("Start: #{correct_date(min).toLocaleString()}")
    else
      @$(".meeting-start").html("&nbsp;")
