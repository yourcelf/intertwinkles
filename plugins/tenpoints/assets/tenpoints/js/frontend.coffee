###########################################################
# Model
############################################################

class TenPointModel extends Backbone.Model
  idAttribute: "_id"

  addHandlers: =>
    intertwinkles.socket.on "tenpoints:tenpoint", @_load
    intertwinkles.socket.on "tenpoints:point", @_pointSet
    intertwinkles.socket.on "tenpoints:support", @_supportSet
    intertwinkles.socket.on "tenpoints:editing", @_edditingSet
    intertwinkles.socket.on "tenpoints:approved", @_approvedSet
    intertwinkles.socket.on "tenpoints:move", @_pointMoved

  removeHandlers: =>
    intertwinkles.socket.off "tenpoints:tenpoint", @_load
    intertwinkles.socket.off "tenpoints:point", @_pointSet
    intertwinkles.socket.off "tenpoints:support", @_supportSet
    intertwinkles.socket.off "tenpoints:editing", @_edditingSet
    intertwinkles.socket.off "tenpoints:approved", @_approvedSet
    intertwinkles.socket.off "tenpoints:move", @_pointMoved

  _load: (data) => @set data.model

  getPoint: (point_id) =>
    return _.find(@get("points"), (p) -> p._id == point_id) or
           _.find(@get("drafts"), (p) -> p._id == point_id)

  _getListPos: (point_id) =>
    for list in [@get("points"), @get("drafts")]
      for point, i in list
        if point._id == point_id
          return [list, i]
    return null

  _matchSupporter: (data, supporter) =>
    d = data
    s = supporter
    return (
      (s.user_id? and d.user_id? and s.user_id == d.user_id) or
      (not s.user_id? and not data.user_id? and
       s.name and d.name and s.name == d.name)
    )

  #
  # Add a new revision to a point, or create a new point with the given text.
  #
  revisePoint: (data, callback) =>
    # Await callback, as this is not an idempotent call.
    intertwinkles.socket.once "tenpoints:point", callback
    intertwinkles.socket.send "tenpoints/revise_point", {
      text: data.text
      point_id: data.point_id
    }
  # Socket push to set a point.
  _pointSet: (data) =>
    point = @getPoint(data.point._id)
    if point?
      _.extend(point, data.point)
      @trigger "change:point:#{point._id}", point
    else
      @get("drafts").push(data.point)
      @trigger "change:drafts"

  #
  # Change your vote for a point
  #
  setSupport: (data, callback) =>
    # Display immediately, then send socket. Response will be idempotent.
    @_supportSet(data)
    intertwinkles.socket.once "tenpoints:support", callback
    intertwinkles.socket.send "tenpoints/support_point", data

  # Socket push for changed votes.
  _supportSet: (data) =>
    point = @getPoint(data.point_id)
    return @fetch() unless point?
    find_supporter = _.find point.supporters, (s) => @_matchSupporter(data, s)
    if data.vote
      if not _.find(point.supporters, find_supporter)
        point.supporters.push({
          user_id: data.user_id
          name: data.name
        })
        @trigger "change:point:#{point._id}"
    else
      point.supporters = _.reject(point.supporters, find_supporter)
      @trigger "change:point:#{point._id}"

  #
  # Set whether we are editing a point.
  #
  setEditing: (data, callback) =>
    # Display immediately, then send socket. Response will be idempotent.
    @_editingSet(data)
    intertwinkles.socket.once "tenpoints:editing", callback
    intertwinkles.socket.send "tenpoints/set_editing", data

  _editingSet: (data) =>
    point = @getPoint(data.point_id)
    return @fetch() unless point?
    point.editing = data.editing
    @trigger "change:point:#{point._id}"

  #
  # Set whether or not a point is approved
  #
  setApproved: (data, callback) =>
    # Display immediately, then send socket. Response will be idempotent.
    @_approvedSet(data)
    intertwinkles.socket.once "tenpoints:approved", callback
    intertwinkles.socket.send "tenpoints/set_approved", data

  # Socket push approval of point
  _approvedSet: (data) =>
    try
      [list, pos] = @_getListPos(data.point_id)
    catch e
      return @fetch()
    if list == @get("drafts") == data.approved
      # We're inconsistent -- we got a message to move something to where it
      # already is.
      console.debug("Inconsistent", data, this)
      return @fetch()
    [point] = list.splice(pos, 1)
    if data.approved
      @get("points").push(point)
    else
      @get("drafts").unshift(point)
    @trigger "change:points"
    @trigger "change:drafts"

  #
  # Move point
  #
  movePoint: (data, callback) =>
    # Wait for return, as this is not idempotent.
    intertwinkles.socket.once "tenpoints:move", callback
    intertwinkles.socket.send "tenpoints/move_point", data

  # Socket push move of point
  _pointMoved: (data) =>
    try
      [list, i] = @_getListPos(data.point_id)
    catch e
      return @fetch()
    [point] = list.splice(i, 1)
    list.splice(data.position, 0, point)
    changed = if list == @get("drafts") then "drafts" else "points"
    @trigger "change:#{changed}"

  #
  # Retrieve all data for this tenpoint.
  #
  fetch: (cb) =>
    return unless @get("slug")
    if cb?
      intertwinkles.socket.once "tenpoints:tenpoint", (data) =>
        @_load(data)
        cb(null, this)
    intertwinkles.socket.send "tenpoints/fetch_tenpoint", {slug: @get("slug")}

  #
  # Save changes to the name, slug, and sharing, but not points/drafts.
  #
  save: (update, opts) =>
    @set(update) if update?
    data = {
      model: {
        _id: @id
        name: @get("name")
        slug: @get("slug")
        sharing: @get("sharing")
      }
    }
    if opts.success? or opts.error?
      intertwinkles.socket.once "tenpoints:tenpoint", (data) =>
        opts.error(data.error) if data.error?
        opts.success(data.model) if data.model?
    intertwinkles.socket.send "tenpoints/save_tenpoint", data

fetchTenPointList = (cb) =>
  intertwinkles.socket.once "tenpoints:list", cb
  intertwinkles.socket.send "tenpoints/fetch_tenpoint_list"

###########################################################
# Views
###########################################################

class TenPointsBaseView extends intertwinkles.BaseView
  events: 'click .softnav': 'softNav'
  initialize: (options={}) ->
    super()
    @model = options.model
  render: =>
    @$el.html(@template())

#
# Front matter
#

class SplashView extends TenPointsBaseView
  template:     _.template $("#splashTemplate").html()
  itemTemplate: _.template $("#splashItemTemplate").html()
  
  initialize: (options) ->
    super(options)
    @setTenPointList(options.tenPointList, false)
    intertwinkles.user.on  "change", @fetchTenPointList, this

  remove: =>
    super()
    intertwinkles.user.off "change", @fetchTenPointList, this

  fetchTenPointList: => fetchTenPointList(@setTenPointList)

  setTenPointList: (data, render=true) =>
    @tenPointList = {
      group: (new TenPointModel(tp) for tp in data.group or [])
      public: (new TenPointModel(tp) for tp in data.public or [])
    }
    if render
      @render()

  render: =>
    @$el.html(@template())
    if @tenPointList.group?.length > 0
      @$(".group-tenpoints").html("<ul></ul>")
      for tenpoint in @tenPointList.group
        @_addItem(".group-tenpoints ul", tenpoint)
    if @tenPointList.public?.length > 0
      @$(".public-tenpoints").html("<ul></ul>")
      for tenpoint in @tenPointList.public
        @_addItem(".public-tenpoints ul", tenpoint)
    intertwinkles.sub_vars(@el)

  _addItem: (selector, tenpoint) =>
    @$(selector).append(@itemTemplate(tenpoint: tenpoint))
  
class EditTenPointView extends TenPointsBaseView
  template: _.template $("#editTemplate").html()
  events:
    'click .softnav': 'softNav'
    'submit    form': 'saveTenPoint'
    'keyup #id_name': 'setSlug'
    'keyup #id_slug': 'checkSlug'

  initialize: (options) ->
    super(options)
    if options?.model.id
      @model = options.model
      @title = "Edit Board Settings"
      @action = "Save"
    else
      @model = new TenPointModel()
      @title = "Add new board"
      @action = "Add board"

  _slugCheck = (show) =>

  setSlug: =>
    unless @model.get("slug")
      @$("#id_slug").val(intertwinkles.slugify(@$("#id_name").val()))
    @checkSlug()

  checkSlug: =>
    val = @$("#id_slug").val()
    parent = @$("#id_slug").closest(".control-group")
    showURL = ->
      parent.find(".url-display").html(
        "#{INTERTWINKLES_APPS.tenpoints.url}/10/#{encodeURIComponent(val)}/"
      )
    if val and val != @model.get("slug")
      intertwinkles.socket.send "tenpoints/check_slug", {slug: val}
      intertwinkles.socket.once "tenpoints:check_slug", (data) =>
        parent.removeClass('error')
        parent.find(".error-msg").remove()
        if data.ok
          showURL()
        else
          parent.addClass('error')
          @$("#id_slug").after(
            "<span class='help-inline error-msg'>Name not available</span>"
          )
          parent.find(".url-display").html("")
    else if val == @model.get("slug")
      showURL()

  render: =>
    @$el.html(@template({
      model: @model.toJSON()
      title: @title
      action: @action
    }))
    @sharing_control?.remove()
    @sharing_control = new intertwinkles.SharingFormControl({
      sharing: @model.get("sharing")
    })
    @addView("#sharing_controls", @sharing_control)
  
  saveTenPoint: (event) =>
    event.preventDefault()
    cleaned_data = @validate()
    if cleaned_data
      @model.save {
        name: cleaned_data.name
        slug: cleaned_data.slug
        number_of_points: cleaned_data.number_of_points
        sharing: @sharing_control.sharing
      }, {
        success: (model) =>
          intertwinkles.app.navigate("/tenpoints/10/#{model.slug}/", {
            trigger: true
          })
      }

  validate: =>
    return @validateFields "form", [
      ["#id_name", ((val) -> $.trim(val) or null), "This field is required."]
      ["#id_slug", ((val) -> $.trim(val) or null), "This field is required."]
      ["#id_number_of_points", (val) ->
        num = parseInt(val, 10)
        if not isNaN(num) and num > 0
          return num
        return null
      , "Number bigger than 0 required"]
    ]

class TenPointView extends TenPointsBaseView
  template: _.template $("#tenpointTemplate").html()
  initialize: (options) ->
    super(options)
    @adder = new EditPointView({model: options.model})

  render: =>
    @$el.html(@template(model: @model.toJSON()))
    @adder.number = @model.get("points")?.length or 0
    @addView(".add-point", @adder)

class PointView extends TenPointsBaseView
  template: _.template $("#pointTemplate").html()

class EditPointView extends TenPointsBaseView
  template: _.template $("#editPointTemplate").html()
  events:
    'click .cancel': 'cancel'
    'click .save': 'save'
    'keydown textarea': 'startEditing'

  initialize: (options) ->
    super(options)
    @number = options.number
    point = @model.get("points")[@number]
    @editing = point and _.contains(point.editing, INITIAL_DATA.anon_id)

  render: =>
    point = @model.get("points")[@number]
    @$el.html(@template({
      model: @model.toJSON()
      number: @number
      point: @model.get("points")[@number]
    }))
    @showEditing()

  showEditing: =>
    @$(".control-line").toggle(@editing)

  startEditing: (event) =>
    unless @editing
      point = @model.get("points")[@number]
      unless point?
        point = {revisions: [{text: ""}], editing: {}}
        @model.get("points").push(point)

    

  cancel: (event) =>
    event.preventDefault()
  save: (event) =>
    event.preventDefault()

###########################################################
# Router
###########################################################

class Router extends Backbone.Router
  routes:
    "tenpoints/10/:slug/point/:point_id/": "pointDetail"
    "tenpoints/10/:slug/history/:point_id/": "history"
    "tenpoints/10/:slug/edit/": "edit"
    "tenpoints/10/:slug/": "board"
    "tenpoints/add/": "add"
    "tenpoints/": "index"

  initialize: ->
    @model = new TenPointModel()
    @model.addHandlers()
    @model.set(INITIAL_DATA.tenpoint or {})
    @tenPointList = INITIAL_DATA.ten_points_list
    @_joinRoom(@model) if @model.id?
    super()

  pointDetail: (slug, point_id) =>
    $("title").html(@model.get("name") + " - Ten Points")
    @_open(
      new PointDetailView({model: @model, point_id: point_id}), slug
    )
  history: (slug, point_id) =>
    $("title").html(@model.get("name") + " - Ten Points")
    @_open(
      new HistoryView({model: @model, point_id: point_id}), slug
    )
  edit: (slug) =>
    $("title").html("Edit " + @model.get("name") + " - Ten Points")
    @_open(new EditTenPointView({model: @model}), slug)
  board: (slug) =>
    $("title").html(@model.get("name") + " - Ten Points")
    @_open(new TenPointView({model: @model}), slug)
  add: =>
    $("title").html("Add - Ten Points")
    @_open(new EditTenPointView({model: @model}), null)
  index: =>
    $("title").html("Ten Points")
    view = new SplashView(tenPointList: @tenPointList)
    if @view?
      fetchTenPointList(view.setTenPointList)
    @_open(view, null)

  onReconnect: =>
    @model.fetch()
    @_joinRoom(@model)

  _open: (view, slug) =>
    if @model.get("slug") and @model.get("slug") != slug
      @_leaveRoom()
    if slug? and not @model.get("slug")?
      @model.set({slug: slug})
      return @model.fetch =>
        $("title").html(@model.get("name") + " - Ten Points")
        @_joinRoom(@model)
        @_showView(view)
    else
      @_showView(view)

  _showView: (view) =>
    @view?.remove()
    $("#app").html(view.el)
    view.render()
    @view = view
    window.scrollTo(0, 0)

  _leaveRoom: =>
    @roomView?.$el.before("<li class='room-users'></li>")
    @roomView?.remove()
    @sharingView?.remove()

  _joinRoom: =>
    @_leaveRoom()

    @roomView = new intertwinkles.RoomUsersMenu(room: "tenpoints/#{@model.id}")
    $(".sharing-online-group .room-users").replaceWith(@roomView.el)
    @roomView.render()

    @sharingView = new intertwinkles.SharingSettingsButton(model: @model)
    $(".sharing-online-group .sharing").html(@sharingView.el)
    @sharingView.render()
    @sharingView.on "save", (sharing) =>
      @model.save {sharing}, {success: => @sharingView.close()}

###########################################################
# Main
###########################################################

app = null
intertwinkles.connect_socket ->
  intertwinkles.build_toolbar($("header"), {applabel: "tenpoints"})
  intertwinkles.build_footer($("footer"))

  unless app?
    app = intertwinkles.app = new Router()
    Backbone.history.start({pushState: true, hashChange: false})
    intertwinkles.socket.on "reconnect", ->
      intertwinkles.socket.once "identified", ->
        app.onReconnect()
