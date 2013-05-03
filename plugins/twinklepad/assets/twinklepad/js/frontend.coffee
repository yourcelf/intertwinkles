tp = {}

class TwinklePad extends Backbone.Model
  # A fine (empty) model.
  save: (callback=(->)) =>
    if @id
      dest = "twinklepad/save_twinklepad"
    else
      dest = "twinklepad/create_twinklepad"
    intertwinkles.socket.send dest, {twinklepad: @toJSON()}
    intertwinkles.socket.once "twinklepad", (data) =>
      @set(data.twinklepad)
      callback()

  fetch: =>
    if @get("pad_name")
      intertwinkles.socket.send "twinklepad/fetch_twinklepad", {
        pad_name: @get("pad_name")
      }
      intertwinkles.socket.once "twinklepad", (data) =>
        @set(data.model)
    else
      console.error "No pad name"

class TwinklePadIndexView extends intertwinkles.BaseView
  template: _.template $("#twinklePadIndexViewTemplate").html()
  events:
    'click .softnav': 'softNav'
  render: =>
    @$el.html(@template())

class EditTwinklePadView extends intertwinkles.BaseView
  template: _.template $("#editTwinklePadViewTemplate").html()
  chars: 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
  events:
    'submit form': 'save'
    'click .softnav': 'softNav'
    'keyup input[name=name]': 'checkName'

  initialize: (options={}) ->
    super()
    @model = options.model or new TwinklePad()
    randomChar = =>
      @chars.substr parseInt(Math.random() * @chars.length), 1
    @randomName = (randomChar() for i in [0...12]).join("")

  render: =>
    @$el.html(@template({
      randomName: @randomName
      model: @model.toJSON()
    }))
    @sharingControl = new intertwinkles.SharingFormControl({
      sharing: @model.get("sharing")
    })
    @addView("#sharing", @sharingControl)

  save: (event) =>
    event.preventDefault()
    return if @$(".error").length > 0
    @model.set {
      pad_name: @$("[name=name]").val() or @randomName
      sharing: @sharingControl.sharing
    }
    @model.save =>
      url = "/twinklepad#{@model.get("url")}"
      intertwinkles.app.navigate url, {trigger: true}

  checkName: (event) =>
    val = @$("#id_name").val()
    parent = @$("#id_name").closest(".control-group")
    if val and val != @model.get("pad_name")
      intertwinkles.socket.send "twinklepad/check_name", {pad_name: val}
      intertwinkles.socket.once "twinklepad:check_name", (data) =>
        parent.find(".error-msg").remove()
        if data.available
          parent.removeClass("error")
          @$("input[type=submit]").attr("disabled", false)
        else
          @$("input[type=submit]").attr("disabled", true)
          parent.addClass("error")
          @$("#id_name").after(
            "<span class='help-inline error-msg'>Name not available</span>"
          )


class TwinklePadView extends intertwinkles.BaseView
  template: _.template $("#twinklePadViewTemplate").html()
  events:
    'click .softnav': 'softNav'

  initialize: (options) ->
    super()
    @model = options.model
    # Sharing control.

    # We won't render this; but just use it for convenience of join/leave logic.
    @room = new intertwinkles.RoomUsersMenu({room: "twinklepad/" + @model.id})
    # Listeners
    @listenTo intertwinkles.socket, "twinklepad", (data) =>
      @model.set(data.twinklepad)
    @listenTo @model, "change:pad_name", @renderName
    @listenTo @model, "change:sharing",  @renderPad
    @listenTo @model, "change:session_cookie", @setCookie
    @listenTo intertwinkles.user, "logout login", @renderPad
    $(window).on "resize", @resize

  remove: =>
    super()
    @room.remove()
    $(window).off "resize", @resize

  setCookie: =>
    # Set authorization for etherpad.
    cookie = @model.get("session_cookie")
    if cookie?
      if cookie.params?.domain == window.location.hostname
        delete cookie.params.domain
      $.cookie("sessionID", cookie.value, cookie.params)

  render: =>
    @setCookie()
    @renderPad()

  renderPad: =>
    embed_url = @model.get("pad_url")
    if intertwinkles.is_authenticated()
      embed_url += ["?userName=",
        encodeURIComponent(intertwinkles.user.get("name")),
        "&userColor=%23",
        encodeURIComponent(intertwinkles.user.get("icon").color)
      ].join("")
    @$el.html(@template({
      editable: intertwinkles.can_edit(@model)
      model: @model.toJSON()
      embed_url: embed_url
    }))
    sharingButton = new intertwinkles.SharingSettingsButton(model: @model)
    sharingButton.on "save", (sharing_settings) =>
      @model.set({sharing: sharing_settings})
      @model.save => sharingButton.close()
    sharingButton.render()
    @$("li.sharing").html(sharingButton.el)
    @resize()

  renderName: =>
    @$(".name, title").html(_.escape(@model.get("pad_name")))
    intertwinkles.app.navigate("/twinklepad#{@model.get("url")}", {
      replace: true, trigger: false
    })

  resize: =>
    window_height = $(window).height() - $("footer").height()
    height = Math.min(
      window_height,
      Math.max(400, window_height - $("iframe").offset().top - 10)
    )
    @$("iframe").css("height", "#{height}px")


class Router extends Backbone.Router
  routes:
    "twinklepad/p/:pad_name/edit/":   "editPad"
    "twinklepad/p/:pad_name/":        "showPad"
    "twinklepad/new/":                 "newPad"
    "twinklepad/":                      "index"

  initialize: ->
    super()
    if INITIAL_DATA.twinklepad
      @model = new TwinklePad(INITIAL_DATA.twinklepad)
    else
      @model = new TwinklePad()

  _open: (view) =>
    @view?.remove()
    $("#app").html(view.el)
    view.render()
    @view = view

  showPad: (pad_name) =>
    pad_name = decodeURIComponent(pad_name)
    @model ?= new TwinklePad()
    if @model.get("pad_name") != pad_name
      @model.set(pad_name: pad_name)
      @model.fetch()
      @model.once "change", =>
        @_open(new TwinklePadView(model: @model))
    else
      @_open(new TwinklePadView(model: @model))

  editPad: (pad_name) =>
    pad_name = decodeURIComponent(pad_name)
    if @model.get("pad_name") != pad_name
      @model.set({pad_name: pad_name})
      @model.fetch()
      @model.once "change", =>
        @_open(new EditTwinklePadView(model: @model))
    else
      @_open(new EditTwinklePadView(model: @model))

  newPad: =>
    @model = new TwinklePad()
    @_open(new EditTwinklePadView(model: @model))

  index: =>
    @_open(new TwinklePadIndexView())

  onReconnect: =>
    @model?.fetch()
    @view?.room?.connect()

app = null
intertwinkles.connect_socket ->
  intertwinkles.build_toolbar($("header"), {applabel: "twinklepad"})
  intertwinkles.build_footer($("footer"), {collapsed: true})
  unless app?
    app = intertwinkles.app = new Router()
    Backbone.history.start({pushState: true, hashChange: false})
    intertwinkles.socket.on "reconnect", ->
      intertwinkles.socket.once "identified", ->
        app.onReconnect()
