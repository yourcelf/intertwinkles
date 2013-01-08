fire = {}

intertwinkles.connect_socket()
intertwinkles.build_toolbar($("header"), {applabel: "firestarter"})
intertwinkles.build_footer($("footer"))

class Firestarter extends Backbone.Model
  idAttribute: "_id"
class Response extends Backbone.Model
  idAttribute: "_id"
class ResponseCollection extends Backbone.Collection
  model: Response
  comparator: (r) ->
    return (new Date(r.get("created")).getTime())


load_firestarter_data = (data) ->
  if not fire.responses?
    fire.responses = new ResponseCollection()
  if data.responses?
    while fire.responses.pop()
      null
    for response in data.responses
      fire.responses.add(new Response(response))
    data.responses = (a._id for a in data.responses)
  if not fire.model?
    fire.model = new Firestarter()
  fire.model.set(data)

#
# Load initial data if any
#
if INITIAL_DATA.firestarter?
  load_firestarter_data(INITIAL_DATA.firestarter)

class SplashView extends Backbone.View
  template: _.template($("#splashTemplate").html())
  itemTemplate: _.template($("#listedFirestarterTemplate").html())

  events:
    "click .new-firestarter": "newFirestarter"
    "click .listed-firestarter a": "softNav"

  initialize: ->
    intertwinkles.user.on "change", @getFirestarterList
    @dateWidgets = []

  remove: =>
    intertwinkles.user.off "change", @getFirestarterList
    for view in @dateWidgets
      view.remove()
    super()

  getFirestarterList: =>
    fire.socket.on "list_firestarters", (data) =>
      if data.error?
        flash "error", "OH my, a server kablooie."
        console.info(data.error)
      else
        INITIAL_DATA.listed_firestarters = data.docs
        @render()
    fire.socket.emit "get_firestarter_list", {callback: "list_firestarters"}

  softNav: (event) =>
    event.preventDefault()
    fire.app.navigate($(event.currentTarget).attr("href"), {trigger: true})

  render: =>
    @$el.html(@template({
      public_docs: INITIAL_DATA.listed_firestarters.public or []
      group_docs: INITIAL_DATA.listed_firestarters.group or []
    }))
    for key in ["group", "public"]
      if INITIAL_DATA.listed_firestarters[key]?.length > 0
        @$(".#{key}-doc-list").html("")
        docs = _.sortBy(INITIAL_DATA.listed_firestarters[key], (d) -> new Date(d.modified).getTime()).reverse()
        for doc in docs
          item = $(@itemTemplate({
            doc: doc
            url: "firestarter/f/#{doc.slug}"
            group: intertwinkles.groups?[doc.sharing.group_id]
          }))
          @$(".#{key}-doc-list").append(item)
          date = new intertwinkles.AutoUpdatingDate(doc.modified)
          $(".date", item).html(date.el)
          date.render()
          @dateWidgets.push(date)

  newFirestarter: (event) =>
    event.preventDefault()
    fire.app.navigate("/firestarter/new", {trigger: true})

class AddFirestarterView extends Backbone.View
  template: _.template($("#addFirestarterTemplate").html())
  events:
    "submit #new_firestarter_form": "createFirestarter"
    "keyup  #id_slug": "displayURL"
    "change #id_slug": "displayURL"

  render: =>
    @$el.html(@template())
    @renderSharingControls()

    @initializeURL()
    @displayURL()

  remove: =>
    @sharing_control?.remove()
    super()

  renderSharingControls: =>
    @sharing_control?.remove()
    @sharing_control = new intertwinkles.SharingFormControl()
    @$("#sharing_controls").html(@sharing_control.el)
    @sharing_control.render()

  displayURL: =>
    val = @$("#id_slug").val()
    val = encodeURIComponent(val)
    if val
      @$(".firestarter-url").html(
        "Firestarter URL: " +
        window.location.protocol + "//" + window.location.host + "/firestarter/f/" + val
      )
    else
      @$(".firestarter-url").html("")

  initializeURL: =>
    fire.socket.once "unused_slug", (data) =>
      @$("#id_slug").val(data.slug)
      @displayURL()
    fire.socket.emit "get_unused_slug", {callback: "unused_slug"}

  createFirestarter: (event) =>
    event.preventDefault()
    @$("#new_firestarter_form .error").removeClass("error")
    @$("#new_firestarter_form .error-msg").remove()
    @$("input[type=submit]").addClass("loading")

    fire.socket.once "create_firestarter", (data) =>
      @$("input[type=submit]").removeClass("loading")
      if data.error?
        if data.type == "ValidationError"
          for error in data.error
            @$("#id_#{error.field}").parentsUntil(
              ".control-group").parent().addClass("error")
            @$("#id_#{error.field}").after(
              "<span class='help-inline error-msg'>#{error.message}</span>"
            )
        else
          alert("Unexpected server error! Oh fiddlesticks!")
      else
        load_firestarter_data(data.model)
        fire.app.navigate("/firestarter/f/#{encodeURIComponent(fire.model.get("slug"))}", {trigger: true})

    fire.socket.emit "create_firestarter", {
      callback: "create_firestarter"
      model: {
        name: @$("#id_name").val()
        prompt: @$("#id_prompt").val()
        slug: @$("#id_slug").val()
        public: @$("#id_public").val()
        sharing: @sharing_control.sharing
      }
    }

class ShowFirestarter extends Backbone.View
  template: _.template $("#firestarterTemplate").html()
  events:
    'click #add_response': 'showAddResponseForm'
    'click .edit-name':    'editName'
    'click .edit-prompt':  'editPrompt'
    'click #id_save_name': 'saveName'
    'click #id_save_prompt': 'savePrompt'

  initialize: (options) ->
    if not fire.model?
      fire.model = new Firestarter()
    if not fire.responses?
      fire.responses = new ResponseCollection()
    @responseViews = []

    @roomUsersMenu = new intertwinkles.RoomUsersMenu({room: options.slug})

    fire.socket.on "firestarter", (data) =>
      console.info "on firestarter", data
      if data.model?
        load_firestarter_data(data.model)
        @sharingButton?.read_only = not intertwinkles.can_change_sharing(fire.model)
        @sharingButton?.render()

    fire.socket.on "response", (data) =>
      response = fire.responses.get(data.model._id)
      if not response?
        response = new Response(data.model)
        fire.responses.add(response)
      else
        response.set(data.model)

    fire.socket.on "delete_response", (data) =>
      fire.responses.remove(fire.responses.get(data.model._id))

    fire.model.on "change", @updateFirestarter, this
    fire.responses.on "add", @addResponseView, this
    fire.responses.on "remove", @removeResponseView, this

    unless fire.model.get("slug") == options.slug
      fire.socket.emit "get_firestarter", {slug: options.slug}

    # Reload sharing settings
    intertwinkles.user.on "change", @refreshFirestarter, this

  remove: =>
    @roomUsersMenu?.remove()
    @sharingButton?.remove()
    @editor?.remove()
    for view in @responseViews
      view.remove()
    fire.socket.removeAllListeners("firestarter")
    fire.socket.removeAllListeners("response")
    fire.socket.removeAllListeners("delete_response")
    fire.model.off null, null, this
    intertwinkles.user.off null, null, this
    delete fire.model
    if fire.responses?
      delete fire.responses
    super()

  refreshFirestarter: =>
    for view in @responseViews
      view.remove()
    fire.socket.emit "get_firestarter", {slug: fire.model.get("slug")}

  editName: (event) =>
    event.preventDefault()
    @$(".edit-name-modal").modal('show').on 'shown', =>
      @$("#id_firestarter_name").focus()
    @$("#id_firestarter_name").val(fire.model.get("name"))

  saveName: (event) =>
    event.preventDefault()
    val = @$("#id_firestarter_name").val()
    @$("#id_save_name").addClass("loading")
    done = =>
      @$("#id_save_name").removeClass("loading")
      @$(".edit-name-modal").modal('hide')

    if val != fire.model.get("name")
      @editFirestarter({name: val}, done)
    else
      done()

  editPrompt: (event) =>
    event.preventDefault()
    @$(".edit-prompt-modal").modal('show').on 'shown', =>
      @$("#id_firestarter_prompt").focus()
    @$("#id_firestarter_prompt").val(fire.model.get("prompt"))

  savePrompt: (event) =>
    event.preventDefault()
    val = @$("#id_firestarter_prompt").val()
    @$("#id_save_prompt").addClass("loading")
    done = =>
      @$("#id_save_prompt").removeClass("loading")
      @$(".edit-prompt-modal").modal('hide')
    if val != fire.model.get("prompt")
      @editFirestarter({prompt: val}, done)
    else
      done()

  editFirestarter: (updates, cb) =>
    fire.socket.once 'firestarter_edited', (data) =>
      if data.error?
        flash "error", "Oh no!  Survur Urrur!"
        console.info(data.error)
      else
        fire.model.set(data.model)
      cb()
    fire.socket.emit "edit_firestarter", {
      callback: 'firestarter_edited'
      model: _.extend({
        _id: fire.model.get("_id")
      }, updates)
    }

  updateFirestarter: =>
    @$(".first-loading").hide()
    @$(".firestarter-name").html(_.escapeHTML(fire.model.get("name")))
    @$(".firestarter-prompt").html(intertwinkles.markup(fire.model.get("prompt")))
    @$(".firestarter-date").html(
      new Date(fire.model.get("created")).toString("htt dddd, MMMM dd, yyyy")
    )

  showAddResponseForm: (event) =>
    event.preventDefault()
    @editResponse(new Response())

  editResponse: (response) =>
    editor = new EditResponseView(model: response)
    @$(".add-response-holder").html(editor.el)
    editor.render()
    @$(".add-response-holder").modal('show').on("shown", -> $("#id_user").focus())
    editor.on "done", =>
      @$(".add-response-holder").modal('hide')
    @editor = editor

  addResponseView: (response) =>
    view = new ShowResponseView(response: response)
    @$(".responses").prepend(view.el)
    view.render()
    view.on "edit", =>
      @editResponse(response)
    view.on "delete", =>
      fire.socket.once "response_deleted", (data) ->
        if data.error?
          flash "error", "Oh No! Server fail..."
          console.info(data.error)
        else
          fire.responses.remove(response)
          fire.model.set({
            responses: _.reject(fire.model.get("responses"), (r) -> r.id == response.id)
          })
      fire.socket.emit "delete_response", {
        callback: "response_deleted"
        model: response.toJSON()
      }
    @responseViews.push(view)

  removeResponseView: (model) =>
    for view in @responseViews
      if view.response.get("_id") == model.get("_id")
        do (view) =>
          view.$el.fadeOut 800, =>
            @responseViews = _.reject @responseViews, (v) =>
              v.response.get("_id") == model.get("_id")
            view.remove()
            return

  render: =>
    # HACK: wait for the model to be ready before rendering.
    unless fire.model?.id
      setTimeout @render, 10
      return
    @sharingButton?.remove()
    @$el.html(@template(read_only: not intertwinkles.can_edit(fire.model)))
    if fire.model? and fire.model.id
      @updateFirestarter()
    if fire.responses?
      for response in fire.responses.models
        @addResponseView(response)
    $(".room-users").replaceWith(@roomUsersMenu.el)
    @roomUsersMenu.render()

    @sharingButton = new intertwinkles.SharingSettingsButton({
      model: fire.model,
      read_only: not intertwinkles.can_change_sharing(fire.model)
    })
    @$(".sharing").html(@sharingButton.el)
    @sharingButton.render()
    @sharingButton.on "save", (sharing_settings) =>
      @editFirestarter({sharing: sharing_settings}, @sharingButton.close)

    # XXX: Make this more efficient, e.g. by limiting to events older than what
    # we already have.
    @buildTimeline()
    build_timeline_timeout = null
    buildWithTimeout = =>
      clearTimeout(build_timeline_timeout) if build_timeline_timeout?
      build_timeline_timeout = setTimeout @buildTimeline, 1000
    fire.model.on "change", buildWithTimeout, null
    fire.responses.on "change add remove", buildWithTimeout, this

  buildTimeline: =>
    if fire.model.id
      callback = "events_" + new Date().getTime()
      fire.socket.once callback, (data) =>
        collection = new intertwinkles.EventCollection()
        for event in data.events
          event.date = new Date(event.date)
          collection.add new intertwinkles.Event(event)
        intertwinkles.build_timeline @$(".timeline-holder"), collection, (event) ->
          user = intertwinkles.users?[event.user]
          via_user = intertwinkles.users?[event.via_user]
          if via_user? and via_user.id == user?.id
            via_user = null
          if user?
            icon = "<img src='#{user.icon.tiny}' />"
          else
            icon = "<i class='icon-user'></i>"
          switch event.type
            when "create"
              title = "Firestarter created"
              content = "#{user?.name or "Anonymous"} created this firestarter."
            when "visit"
              title = "Visit"
              content = "#{user?.name or "Anonymous"} stopped by."
            when "append"
              title = "Response added"
              if via_user?
                content = "#{user?.name or event.data.name} responded (via #{via_user.name})."
              else
                content = "#{user?.name or event.data.name} responded."
            when "update"
              title = "Firestarter updated"
              content = "#{user?.name or "Anonymous"} updated the firestarter."
            when "trim"
              title = "Response removed"
              content = "#{user?.name or "Anonymous"} removed a response by #{event.data.name}."
          return """
            <a class='#{ event.type }' rel='popover' data-placement='bottom'
               data-trigger='hover' title='#{ title }'
               data-content='#{ content }'>#{ icon }</a>
          """

      fire.socket.emit "get_firestarter_events", {
        callback: callback,
        firestarter_id: fire.model.id
      }

class EditResponseView extends Backbone.View
  template: _.template $("#editResponseTemplate").html()
  events:
    'submit #edit_response_form': 'saveResponse'
    'click .cancel': 'cancel'

  initialize: (options={}) =>
    @model = options.model or new Response()

  remove: =>
    @user_choice?.remove()
    super()

  cancel: =>
    @trigger "done"

  render: =>
    context = _.extend({
      response: ""
      read_only: not intertwinkles.can_edit(fire.model)
    }, @model.toJSON())
    context.verb = if @model.get("_id") then "Save" else "Add"
    @$el.html @template(context)

    @user_choice = new intertwinkles.UserChoice(model: @model)
    @$("#name_controls").html @user_choice.el
    @user_choice.render()

  saveResponse: (event) =>
    event.preventDefault()
    @$("#edit_response_form input[type=submit]").addClass("loading")
    @$(".error").removeClass("error")
    @$(".error-msg").remove()
    errors = false

    name = @$("#id_user").val()
    if not name
      @$("#id_user").parentsUntil(".control-group").parent().addClass("error")
      @$("#id_user").append("<span class='help-text error-msg'>This field is required</span>")
      errors = true
    response = @$("#id_response").val()
    if not response
      @$("#id_response").parentsUntil(".control-group").parent().addClass("error")
      @$("#id_response").append("<span class='help-text error-msg'>This field is required</span>")
      errors = true

    if errors
      @$("#edit_response_form input[type=submit]").removeClass("loading")
    else
      updates = {
        _id: @model.get("_id")
        user_id: @$("#id_user_id").val()
        name: name
        response: response
        firestarter_id: fire.model.id
      }
      fire.socket.once "response_saved", (data) =>
        if data.error
          flash "error", "Oh noes. SERVER ERROR. !!"
          console.info data.error
        else
          add_it = not @model.get("_id")?
          @model.set(data.model)
          if add_it
            fire.responses.add(@model)
          @trigger "done"
      fire.socket.emit "save_response", { callback: "response_saved", model: updates }

class ShowResponseView extends Backbone.View
  template: _.template $("#responseTemplate").html()
  events:
    'click .really-delete': 'deleteResponse'
    'click .delete': 'confirmDelete'
    'click .edit':   'editResponse'

  initialize: (options={}) ->
    @response = options.response
    @response.on "change", @render
    intertwinkles.user.on "change", @render, this

  remove: =>
    @response.off "change", @render
    intertwinkles.user.off "change", @render
    @date?.remove()
    super()

  render: =>
    @$el.addClass("firestarter-response")
    context = @response.toJSON()
    context.read_only = not intertwinkles.can_edit(fire.model)
    @$el.html(@template(context))
    @date = new intertwinkles.AutoUpdatingDate(@response.get("created"))
    @$(".date-holder").html @date.el
    @date.render()
    @$el.effect("highlight", {}, 3000)

  confirmDelete: (event) =>
    event.preventDefault()
    @$(".delete-confirmation").modal('show')

  deleteResponse: (event) =>
    event.preventDefault()
    @$(".delete-confirmation").modal('hide')
    @trigger "delete", @response

  editResponse: (event) =>
    event.preventDefault()
    @trigger "edit", @response

class Router extends Backbone.Router
  routes:
    'firestarter/f/:room': 'room'
    'firestarter/new':     'newFirestarter'
    'firestarter/':        'index'

  index: =>
    @view?.remove()
    @view = new SplashView()
    $("#app").html(@view.el)
    @view.render()

  newFirestarter: =>
    @view?.remove()
    @view = new AddFirestarterView()
    $("#app").html(@view.el)
    @view.render()

  room: (roomName) =>
    @view?.remove()
    slug = decodeURIComponent(roomName)

    @view = new ShowFirestarter({slug: slug})
    $("#app").html(@view.el)
    @view.render()

fire.firestarter_url = (slug) ->
  return "#{INTERTWINKLES_APPS["firestarter"].url}/firestarter/f/#{slug}"

socket = io.connect("/io-firestarter")
socket.on "error", (data) ->
  flash("error", "Oh hai, the server has ERRORed. Oh noes!")
  window.console?.log?(data.error)

socket.on "connect", ->
  fire.socket = socket
  unless fire.started == true
    fire.app = new Router()
    Backbone.history.start(pushState: true, silent: false)
    fire.started = true

