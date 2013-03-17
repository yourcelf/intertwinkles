###########################################################
# Model
###########################################################

BROWSER_CLOCK_SKEW = 0

class ClockModel extends Backbone.Model
  idAttribute: "_id"
  initialize: (options) ->
    super(options)
    intertwinkles.socket.on "clock", @_load
    intertwinkles.socket.on "clock:time", @_setTime

  _load: (data) =>
    @set data.model
    @_setSkiew(data)

  _setTime: (data) =>
    @_setSkiew(data)
    categories = @model.get("categories")
    category = categories?[data.category]
    return @fetch() if not category
    if category.times[data.index]
      category.times[data.index] = data.time
    else if category.times.length == data.index
      category.times.push(data.time)
    else
      return @fetch()
    @set("categories", categories)
    @trigger "change:categories:#{category_name}", this

  _setSkew: (data) ->
    if data.now?
      BROWSER_CLOCK_SKEW = new Date(data.now).getTime() - new Date().getTime()

  _now: -> new Date(new Date().getTime() + BROWSER_CLOCK_SKEW)

  fetch: (cb) =>
    return unless @id
    fetch = {_id: @id}
    # If we get a callback, specify a callback parameter for the query. If not,
    # leave it blank, and the result will be sent to "clock" and handled by
    # @_load directly.
    if cb?
      intertwinkles.socket.once "clock_cb", (data) ->
        @_load(data)
        cb(null, this)
      fetch.callback = 'clock_cb'
    intertwinkles.socket.emit "clock/fetch_clock", fetch

  save: (update, options) =>
    @set(update) if update?
    intertwinkles.socket.emit "clock/save_clock", {model: this.toJSON()}

  start: (category_name) =>
    categories = @model.get("categories")
    category = categories[category_name]
    # Skip out if we're already counting.
    return if not category.times[category.times.length - 1].stop
    new_time = {start: @_now()}
    category.times.push({start: new Date()})
    intertwinkles.socket.emit "clock/set_time", {
      _id: @model.id
      category: category_name
      time: new_time
      index: category.times.length - 1
      now: new Date()
    }
    @set "categories", categories
    @trigger "change:categories:#{category_name}", this

  stop: (category_name) =>
    categories = @model.get("categories")
    category = categories[category_name]
    # Skip out if we aren't counting.
    return if category.times[category.time.length - 1].stop?
    time = category.times[category.time.length - 1]
    time.stop = @_now()
    intertwinkles.socket.emit "clock/set_time", {
      _id: @model.id
      category: category_name
      time: time
      index: category.times.length - 1
      now: new Date()
    }
    @set "categories", categories
    @trigger "change:categories:#{category_name}", this

fetch_clock_list: (cb) =>
  intertwinkles.socket.once "clock_list", cb
  intertwinkles.socket.emit "clock/fetch_clock_list"

###########################################################
# Views
###########################################################

class ClockBaseView extends intertwinkles.BaseView
  events: 'click .softnav': 'softNav'
  render: =>
    @$el.html(@template())

#
# Front matter
#

class SplashView extends ClockBaseView
  template: _.template $("#splashTemplate").html()

class AboutView extends ClockBaseView
  template: _.template $("#aboutTemplate").html()

#
# Adding / editing
#

class EditView extends ClockBaseView
  template: _.template $("#editTemplate").html()
  events:
    'click .softnav': 'softNav'
    'submit form':    'addClock'
    'keyup input':    'validate'

  initialize: (options) ->
    super()
    if options?.model
      @model = options.model
      @title = "Edit Clock Settings"
      @action = "Save settings"
    else
      @model = new ClockModel()
      @title = "Add new Clock"
      @action = "Add clock"

  render: =>
    @$el.html(@template({
      model: @model.toJSON()
      title: @title
      action: @action
    }))
    @sharing_contorl?.remove()
    @sharing_control = new intertwinkles.SharingFormControl({
      sharing: @model.get("sharing")
    })
    @addView("#sharing_controls", @sharing_control)

    items = (c.name for c in @model.get("names") or [])
    if items.length == 0
      items = ["Male", "Female", "Person of Color", "White"]
    @items_control = new ItemsListView({items: items})
    @addView("#category_controls", @items_control)

  addClock: (event) =>
    cleaned_data = @validate()
    if cleaned_data
      console.log cleaned_data
      old_cats = @model.get('categories') or []
      new_cats = []
      for name,i in cleaned_data.categories
        if name and old_cats[i]
          new_cats.push({ name: name, times: old_cats[i].times })
        else if name
          new_cats.push({ name: name, times: [] })

      @model.save({
        name: cleaned_data.name
        sharing: @sharing_control.sharing
        categories: new_cats
      }, {
        success: (model) =>
          intertwinkles.app.navigate("/clock/c/#{model.id}/", {
            trigger: true
          })
      })

  validate: =>
    cleanCategories = =>
      items = ($.trim(a) for a in @items_control.readItems())
      non_blank = (a for a in items when a)
      if non_blank.length > 0
        return items
      else
        return null
    return @validateFields "form", [
      ["#id_name", ((val) -> $.trim(val) or null), "This field is required."]
      ["#category_controls [name=item-0]", cleanCategories, "At least one category is required.", "categories"]
    ]

class ItemsListView extends ClockBaseView
  template: _.template $("#itemsListTemplate").html()
  itemTemplate: _.template $("#itemsListItemTemplate").html()
  events:
    'click .sftnav': 'softNav'
    'click .add': 'addItem'
    'click .remove-item': 'removeItem'
    'keydown .item': 'enterItem'

  initialize: (options) ->
    super()
    @items = options?.items or []

  render: =>
    @$el.html(@template())
    @renderItems()

  readItems: => _.map @$("input.item"), (el) -> $(el).val()

  enterItem: (event) =>
    if event.keyCode == 13
      @addItem()
    if event.keyCode == 8 && $(event.currentTarget).val() == ""
      @removeItem(event)
      @$(".item:last").focus()

  addItem: =>
    @items = @readItems()
    @items.push("")
    @renderItems()
    @$(".item:last").select()

  removeItem: (event) =>
    @items = @readItems()
    index = $(event.currentTarget).attr("data-index")
    @items.splice(index, 1)
    @renderItems()

  renderItems: =>
    @$(".items").html("")
    if @items.length == 0
      @items.push("")
    for item,i in @items
      @$(".items").append(@itemTemplate({
        value: item
        name: "item-#{i}"
        index: i
        last: @items.length == 1
      }))

# Form widget for marking who is present.
class PresentControlsView extends ClockBaseView
  template: _.template $("#presentControlsTemplate").html()
  events:
    'click .softnav': 'softNav'

#
# Detail view
#

class ClockView extends ClockBaseView
  template: _.template $("#timeKeeperTemplate").html()
  events:
    'click .softnav': 'softNav'
    'click .settings': 'settings'
    'click .graph': 'graph'
    'click .reset': 'reset'

  initialize: (options) ->
    super()
    @model = options.model
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
        catview = new CategoryTimerView(model, i)
        @$(".category-list").append(catview.el)
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

# View for the button with built-in category timer.
class CategoryTimerView extends ClockBaseView
  template: _.template $("#categoryTimerTemplate").html()
  events:
    'click .softnav': 'softNav'
    'mousedown a.activate': 'mouseToggleActive'
    'touchstart a.activate': 'touchToggleActive'

  initialize: (options) ->
    super()
    @model = options.model
    @category = options.category
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

# View for a simple clock displaying the current time.
class CurrentTimeView extends ClockBaseView
  template: _.template $("#currentTimeTemplate").html()
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
    
#
# Reviewing
#

class GraphView extends ClockBaseView
  template: _.template $("#graphTemplate").html()
  events:
    'click .softnav': 'softNav'

class ExportView extends ClockBaseView
  template: _.template $("#exportTemplate").html()
  events:
    'click .softnav': 'softNav'

###########################################################
# Router
###########################################################

class Router extends Backbone.Router
  routes:
    "clock/c/:id/edit/":    "edit"
    "clock/c/:id/graph/":   "graph"
    "clock/c/:id/export/":  "export"
    "clock/c/:id/":         "showClock"
    "clock/about/":         "about"
    "clock/add/":           "addClock"
    "clock/":               "index"

  initialize: (options) ->
    @model = new ClockModel(options.socket)
    @model.set(INITIAL_DATA.clock or {})
    @_join_room(@model) if @model.id?
    super()

  edit: (id) =>       @_open(new EditView(model: @model), id)
  graph: (id) =>      @_open(new GraphView(model: @model), id)
  export: (id) =>     @_open(new ExportView(model: @model), id)
  showClock: (id) =>  @_open(new ClockView(model: @model), id)
  about: =>           @_open(new AboutView())
  addClock: =>        @_open(new EditView())
  index: =>
    view = new SplashView()
    if @view?
      # Re-fetch list if this isn't a first load.
      fetch_clock_list (data) => view.set_clock_list(data)
    @_open(view, null)

  onReconnect: =>
    # refresh data after a disconnection.

  _open: (view, id) =>
    console.log view
    if @model.id? and @model.id != id
      @_leave_room()
      if id?
        @model.set({_id: id})
        return @model.fetch =>
          @_join_room(@model)
          @_show_view(view)
    @_show_view(view)
    
  _show_view: (view) =>
    @view?.remove()
    $("#app").html(view.el)
    view.render()
    @view = view

  _leave_room: =>
    @room_view?.remove()
    @sharing_view?.remove()

  _join_room: (model) =>
    @_leave_room()

    @room_view = new intertwinkles.RoomUsersMenu(room: @model.id)
    $(".sharing-online-group .room-users").replaceWith(@room_view.el)
    room_view.render()

    @sharing_view = new intertwinkles.SharingSettingsButton(model: @model)
    $(".sharing-online-group .sharing").html(@sharing_view.el)
    @sharing_view.render()
    @sharing_view.on "save", (sharing_settings) =>
      @model.set { sharing: sharing_settings }
      @model.send_update()
      @sharing_view.close()

###########################################################
# Utils
###########################################################

correct_date = (date) ->
  time = if date.getTime? then date.getTime() else date
  time += browser_server_time_offset
  return new Date(time)

###########################################################
# Main
###########################################################

app = null
intertwinkles.connect_socket ->
  intertwinkles.build_toolbar($("header"), {applabel: "clock"})
  intertwinkles.build_footer($("footer"))

  unless app?
    app = intertwinkles.app = new Router(socket: intertwinkles.socket)
    Backbone.history.start(pushState: true)
    intertwinkles.socket.on "reconnected", ->
      intertwinkles.socket.once "identified", ->
        app.onReconnect()
