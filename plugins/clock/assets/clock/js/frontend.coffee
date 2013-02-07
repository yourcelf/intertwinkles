intertwinkles.connect_socket()
intertwinkles.build_toolbar($("header"), {applabel: "clock"})
intertwinkles.build_footer($("footer"))

BROWSER_CLOCK_SKEW = 0

class ProgTime extends Backbone.Model
  idAttribute: "_id"
  initialize: (socket) ->
    super()
    @socket = socket
    @socket.on "progtime", @_load

  _load: (data) =>
    if data.error?
      flash "error", "Server error"
      console.log data.error
      return false
    else
      @set data.model
      if data.now?
        BROWSER_CLOCK_SKEW = new Date(data.now).getTime() - new Date().getTime()
      return true

  fetch: (cb) =>
    return unless @id
    @socket.once "fetch_progtime", (data) ->
      if @_load(data)
        cb(null, this)
    @socket.emit "fetch_progtime", {_id: @id}

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

class SettingsView extends Backbone.View
  template: _.template $("#settings").html()
  max_num_categories: 8
  events:
    'submit form': 'save'
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

class TimeKeeperView extends Backbone.View
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

class SplashView extends Backbone.View

class Router extends Backbone.Router
  routes:
    "c/:id/settings": "settings"
    "c/:id/graph":    "graph"
    "c/:id/about":    "about"
    "c/:id/":         "timekeeper"
    "":               "index"

  initialize: (socket) ->
    @model = new ProgTime(socket)
    @model.set(INITIAL_DATA.progtime or {})
    @_join_room(@model) if @model.id?
    super()

  timekeeper: (id) => @_open(new TimeKeeperView(@model), id)
  settings: (id) =>   @_open(new SettingsView(@model), id)
  graph: (id) =>      @_open(new GraphView(@model), id)
  about: (id) =>      @_open(new AboutView(@model), id)
  index: =>
    view = new SplashView()
    if @view?
      # Re-fetch list if this isn't a first load.
      @model.fetch_progtime_list (data) =>
        view.set_progtime_list(data.progtimes)
    @_open(view, null)

  _open: (view, id) =>
    if model.id != id
      @_leave_room()
      if id?
        model.set({_id: id})
        return model.fetch =>
          @_join_room(model)
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

correct_date = (date) ->
  time = if date.getTime? then date.getTime() else date
  time += browser_server_time_offset
  return new Date(time)
  
app = null
socket.on "error", (data) ->
  flash "error", "Socket server error, sorrry!"
  console.log(data)
socket.on "connect", ->
  unless app?
    app = intertwinkles.app = new Router(socket)
    Backbone.history.start({ pushState: true, root: "/clock/"})
  
socket = io.connect("/io-clock")


