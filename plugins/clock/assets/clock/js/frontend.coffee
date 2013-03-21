###########################################################
# Model
###########################################################

BROWSER_CLOCK_SKEW = 0

class ClockModel extends Backbone.Model
  idAttribute: "_id"
  initialize: (options) ->
    super(options)

  setHandlers: =>
    intertwinkles.socket.on "clock", @_load
    intertwinkles.socket.on "clock:time", @_setTime

  _load: (data) =>
    console.log "load", data
    @set data.model
    @_setSkew(data)

  _setTime: (data) =>
    console.log "set time", data
    @_setSkew(data)
    categories = @get("categories")
    category = _.find categories, (c) -> c.name == data.category
    return @fetch() if not category
    if category.times[data.index]
      for key in ["start", "stop"]
        if intertwinkles.parse_date(category.times[data.index][key]) != intertwinkles.parse_date(data.time[key])
          category.times[data.index] = data.time
          @trigger "change:categories:#{category.name}", this
          return
    else if category.times.length == data.index
      category.times.push(data.time)
      @trigger "change:categories:#{category.name}", this
      return
    else
      return @fetch()

  _setSkew: (data) =>
    if data.now?
      BROWSER_CLOCK_SKEW = intertwinkles.parse_date(data.now).getTime() - new Date().getTime()

  _now: -> new Date(new Date().getTime() + BROWSER_CLOCK_SKEW)

  fetch: (cb) =>
    console.log "fetch", @id
    return unless @id
    fetch = {_id: @id}
    # If we get a callback, specify a callback parameter for the query. If not,
    # leave it blank, and the result will be sent to "clock" and handled by
    # @_load directly.
    if cb?
      intertwinkles.socket.once "clock_cb", (data) =>
        @_load(data)
        cb(null, this)
      fetch.callback = 'clock_cb'
    intertwinkles.socket.send "clock/fetch_clock", fetch

  save: (update, options) =>
    @set(update) if update?
    update = {model: {
      _id: @id
      name: @get("name")
      about: @get("about")
      categories: @get("categories")
      present: @get("present")
      sharing: @get("sharing")
    }}
    if options.success? or options.error?
      update.callback = "save_cb"
      intertwinkles.socket.once update.callback, (data) ->
        options.error(data.error) if data.error?
        options.success(data.model) if data.model?
    intertwinkles.socket.send "clock/save_clock", update

  start: (category_name) =>
    categories = @get("categories")
    category = _.find(categories, (c) -> c.name == category_name)
    # Skip out if we're already counting.
    return if (category.times.length > 0 and
      not category.times[category.times.length - 1].stop)
    new_time = {start: @_now()}
    category.times.push(new_time)
    intertwinkles.socket.send "clock/set_time", {
      _id: @id
      category: category_name
      time: new_time
      index: category.times.length - 1
      now: new Date()
    }
    @trigger "change:categories:#{category_name}", this

  stop: (category_name) =>
    categories = @get("categories")
    category = _.find(categories, (c) -> c.name == category_name)
    # Skip out if we aren't counting.
    return if (category.times.length == 0 or
      category.times[category.times.length - 1].stop?)
    time = category.times[category.times.length - 1]
    time.stop = @_now()
    intertwinkles.socket.send "clock/set_time", {
      _id: @id
      category: category_name
      time: time
      index: category.times.length - 1
      now: new Date()
    }
    @trigger "change:categories:#{category_name}", this

  getStartDate: =>
    min = Number.MAX_VALUE
    for cat in @get("categories") or []
      if cat.times.length > 0
        min = Math.min(min, intertwinkles.parse_date(cat.times[0].start).getTime())
    if min == Number.MAX_VALUE
      return null
    return new Date(min)

  getEndDate: =>
    max = Number.MIN_VALUE
    for cat in @get("categories") or []
      if cat.times.length > 0
        end = cat.times[cat.times.length - 1].end or new Date()
        max = Math.max(max, intertwinkles.parse_date(end).getTime())
    if max == Number.MIN_VALUE
      return null
    return new Date(max)

  getElapsed: (category_name) =>
    category = _.find @get("categories"), (c) -> c.name == category_name
    return null unless category?
    elapsed = 0
    for time in category.times
      start = intertwinkles.parse_date(time.start)
      if time.stop
        stop = intertwinkles.parse_date(time.stop)
      else
        stop = correct_date(new Date())
      elapsed += stop.getTime() - start.getTime()
    return elapsed

fetch_clock_list = (cb) =>
  intertwinkles.socket.once "clock_list", (data) ->
    cb(data)
  intertwinkles.socket.send "clock/fetch_clock_list"

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
  itemTemplate: _.template $("#splashItemTemplate").html()
  initialize: (options) ->
    @set_clock_list(options.clock_list, false)
    intertwinkles.user.on "change", @fetch_clock_list, this

  remove: =>
    super()
    intertwinkles.user.off "change", @fetch_clock_list, this

  fetch_clock_list: =>
    fetch_clock_list (list) =>
      @set_clock_list(list)

  set_clock_list: (data, render=true) =>
    @clock_list = {
      group: (new ClockModel(c) for c in data.group)
      public: (new ClockModel(c) for c in data.public)
    }
    if render
      @render()

  render: =>
    @$el.html(@template())
    if @clock_list.group?.length > 0
      @$(".group-clocks").html("<ul></ul>")
      for clock in @clock_list.group
        @_add_item(".group-clocks ul", clock)
    if @clock_list.public?.length > 0
      @$(".public-clocks").html("<ul></ul>")
      for clock in @clock_list.public
        @_add_item(".public-clocks ul", clock)
    intertwinkles.sub_vars(@el)

  _add_item: (selector, clock) =>
    @$(selector).append(@itemTemplate(clock: clock))

class AboutView extends ClockBaseView
  template: _.template $("#aboutTemplate").html()

#
# Adding / editing
#

class EditView extends ClockBaseView
  template: _.template $("#editTemplate").html()
  events:
    'click .softnav': 'softNav'
    'submit form':    'saveClock'
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

    items = (c.name for c in @model.get("categories") or [])
    if items.length == 0
      items = ["Male", "Female", "Person of Color", "White"]
    @items_control = new ItemsListView({items: items})
    @addView("#category_controls", @items_control)

    if @model.id
      @addView(".clock-footer", new ClockFooterView({
        current: "edit", model: @model
      }))

  saveClock: (event) =>
    event.preventDefault()
    cleaned_data = @validate()
    if cleaned_data
      old_cats = @model.get('categories') or []
      new_cats = []
      for name,i in cleaned_data.categories
        if name and old_cats[i]
          new_cats.push({ name: name, times: old_cats[i].times })
        else if name
          new_cats.push({ name: name, times: [] })

      @model.save({
        name: cleaned_data.name
        about: cleaned_data.about
        sharing: @sharing_control.sharing
        categories: new_cats
      }, {
        success: (model) =>
          intertwinkles.app.navigate("/clock/c/#{model.id}/", {trigger: true})
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
      ["#id_about", ((val) -> val), ""]
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
  template: _.template $("#clockTemplate").html()
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
    for view in @catviews or []
      view?.remove()
    @current_time?.remove()

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
    
    # Category views
    for cat,i in @model.get("categories") or []
      catview = new CategoryTimerView({model: @model, category: cat})
      @$(".category-list").append(catview.el)
      catview.render()
      @catviews.push(catview)
    
    # Starting time
    start_date = @model.getStartDate()
    if start_date
      @$(".meeting-start").html("Start: #{correct_date(start_date).toLocaleString()}")
    else
      @$(".meeting-start").html("&nbsp;")

    # Current time
    @current_time = new CurrentTimeView()
    @$(".current-time").html(@current_time.el)
    @current_time.render()

    # Footer
    @footer = new ClockFooterView({current: "clock", model: @model})
    @$(".clock-footer").html(@footer.el)
    @footer.render()

# View for the button with built-in category timer.
class CategoryTimerView extends ClockBaseView
  tagName: 'a'
  template: _.template $("#categoryTimerTemplate").html()
  events:
    'mousedown':  'mouseToggleActive'
    'touchstart': 'touchToggleActive'
    'click':      'none'

  initialize: (options) ->
    super()
    @model = options.model
    @category = options.category
    @model.on "change", @render, this
    @model.on "change:categories:#{@category.name}", @render, this

  remove: =>
    @model.off null, null, this
    clearInterval(@goer) if @goer?
    super()

  isActive: =>
    return @category.times?.length > 0 and (
      not @category.times[@category.times.length - 1].stop?
    )

  none: (event) =>
    event.stopPropagation()
    event.preventDefault()

  mouseToggleActive: (event) =>
    event.stopPropagation()
    event.preventDefault()
    return false unless intertwinkles.can_edit(@model)
    @toggleActive() unless @touchIsEnabled
    return false

  touchToggleActive: (event) =>
    event.stopPropagation()
    event.preventDefault()
    return false unless intertwinkles.can_edit(@model)
    @touchIsEnabled = true
    @toggleActive()
    return false

  toggleActive: (event) =>
    if @isActive()
      @model.stop(@category.name)
      @render()
    else
      @model.start(@category.name)
      @render()

  get_elapsed: =>
    elapsed = @model.getElapsed(@category.name)
    if elapsed == null and @goer?
      clearInterval(@goer)
    seconds = Math.round(elapsed / 1000) % 60
    seconds = if seconds < 10 then "0" + seconds else seconds
    minutes = Math.floor(elapsed / 1000 / 60)
    return "#{minutes}:#{seconds}"

  render: =>
    active = @isActive()
    @$(".active").removeClass("active")
    @$el.attr({
      href: "#"
      class: "btn timer-button #{if active then "active btn-warning" else "btn-success"}"
    }).html(
      @template({name: @category.name or "Undefined"})
    )
    
    # Show elapsed time.
    go = => @$(".elapsed").html(@get_elapsed())
    go()
    # Remove any previous interval for incrementing the time.
    if @goer? then clearInterval(@goer)
    # Set up a new interval to increment the time if we're active.
    if active then @goer = setInterval(go, 100)

# View for a simple clock displaying the current time.
class CurrentTimeView extends ClockBaseView
  render: =>
    @$el.addClass("current-time")
    go = =>
      @$el.html(
        # Remove seconds
        new Date().toLocaleTimeString().replace(/0?(\d+:\d+)(:\d+)(.*)/, "$1$3")
      )
    go()
    clearInterval(@goer) if @goer?
    @goer = setInterval(go, 1000)
    this

  remove: =>
    clearInterval @goer if @goer?
    super()

#
# Clock footer view
#
class ClockFooterView extends ClockBaseView
  template: _.template $("#clockFooterTemplate").html()
  initialize: (options) ->
    @current = options.current
    @model = options.model
    @model.on "change", @render, this
    intertwinkles.user.on("change", @render, this)

  remove: =>
    super()
    intertwinkles.user.off("change", @render, this)
    @model.off "change", @render, this

  render: =>
    links = []
    # key, display_name, url
    links.push(["clock", "Clock", "/clock/c/#{@model.id}/"])
    if intertwinkles.can_edit(@model)
      links.push(["edit", "Edit", "/clock/c/#{@model.id}/edit/"])
    links.push(["graph", "Graph", "/clock/c/#{@model.id}/graph/"])
    links.push(["export", "Export", "/clock/c/#{@model.id}/export/"])
    @$el.html(@template({links: links, current: @current}))


#
# Reviewing
#

class GraphView extends ClockBaseView
  template: _.template $("#graphTemplate").html()
  events:
    'click .softnav': 'softNav'
  initialize: (options) ->
    super()
    @model = options.model

  render: =>
    startDate = @model.getStartDate()
    endDate   = @model.getEndDate()
    @$el.html(@template({
      startDate: startDate
      endDate: endDate
      categories: @model.get("categories")
    }))
    @addView(".clock-footer", new ClockFooterView({
      model: @model
      current: "graph"
    }))

    return unless startDate and endDate

    startTime = startDate.getTime()
    endTime = endDate.getTime()
    totalTime = endTime - startTime

    @$(".time-block").each (i, el) ->
      $el = $(el)
      start = parseInt($el.attr("data-start"))
      end = parseInt($el.attr("data-stop"))
      leftPercent = 100 * (start - startTime) / totalTime
      widthPercent = 100 * (end - start) / totalTime
      $(el).css({
        left: leftPercent + "%"
        width: widthPercent + "%"
      })
    @$(".time-block").tooltip()



class ExportView extends ClockBaseView
  template: _.template $("#exportTemplate").html()
  events:
    'click .softnav': 'softNav'
    'click .json': 'showJSON'
    'click .csv': 'showCSV'
  initialize: (options) ->
    super()
    @model = options.model
    @active = "json"

  render: =>
    @$el.html(@template({
      model: @model
      startDate: @model.getStartDate()
      active: @active
      data: if @active == "json" then @getJSON() else @getCSV()
    }))
    @addView(".clock-footer", new ClockFooterView({current: "export", model: @model}))

  showJSON: => @active = "json" ; @render()
  showCSV:  => @active = "csv"  ; @render()

  getJSON: =>
    data = {
      name: @model.get("name")
      startDate: @model.getStartDate()
      categories: []
    }
    for cat in @model.get("categories")
      catData = {
        name: cat.name
        times: []
      }
      for time in cat.times
        catData.times.push({start: time.start, stop: time.stop})
      catData.elapsed = @model.getElapsed(cat.name)
      data.categories.push(catData)
    return JSON.stringify(data, null, "  ")

  getCSV: =>
    csvEscape = (str) ->
      str = $.trim(str).replace(/"/, '""')
      if str.indexOf(",") != -1
        str = '"' + str + '"'
      return str

    rows = []
    for cat in @model.get("categories")
      for time in cat.times
        rows.push([
          csvEscape(cat.name),
          csvEscape(time.start),
          csvEscape(time.stop)
        ])
    rows = _.sortBy(rows, (r) -> r[1])
    rows.unshift(["Category","Start","Stop"])
    return (row.join(",") for row in rows).join("\n")

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
    @model.setHandlers()
    @model.set(INITIAL_DATA.clock or {})
    @clock_list = INITIAL_DATA.clock_list
    @_join_room(@model) if @model.id?
    super()

  edit: (id) =>       @_open(new EditView(model: @model), id)
  graph: (id) =>      @_open(new GraphView(model: @model), id)
  export: (id) =>     @_open(new ExportView(model: @model), id)
  showClock: (id) =>  @_open(new ClockView(model: @model), id)
  about: =>           @_open(new AboutView())
  addClock: =>        @_open(new EditView())
  index: =>
    view = new SplashView(clock_list: @clock_list)
    if @view?
      # Re-fetch list if this isn't a first load.
      fetch_clock_list (data) =>
        view.set_clock_list(data)
    @_open(view, null)

  onReconnect: =>
    @model.fetch()
    @_join_room(@model)

  _open: (view, id) =>
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
    window.scrollTo(0, 0)

  _leave_room: =>
    console.log "leave!", @model.get("name")
    @room_view?.$el.before("<li class='room-users'></li>")
    @room_view?.remove()
    @sharing_view?.remove()

  _join_room: (model) =>
    @_leave_room()
    console.log "join!", model.get("name")

    @room_view = new intertwinkles.RoomUsersMenu(room: "clock/#{@model.id}")
    $(".sharing-online-group .room-users").replaceWith(@room_view.el)
    @room_view.render()

    @sharing_view = new intertwinkles.SharingSettingsButton(model: @model)
    $(".sharing-online-group .sharing").html(@sharing_view.el)
    @sharing_view.render()
    @sharing_view.on "save", (sharing_settings) =>
      @model.save({sharing: sharing_settings}, {
        success: =>
          @sharing_view.close()
      })

###########################################################
# Utils
###########################################################

correct_date = (date) ->
  time = if date.getTime? then date.getTime() else date
  time += BROWSER_CLOCK_SKEW
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
    Backbone.history.start({pushState: true, hashChange: false})
    intertwinkles.socket.on "reconnected", ->
      intertwinkles.socket.once "identified", ->
        app.onReconnect()
