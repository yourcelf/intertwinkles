fire = {}

class Firestarter extends Backbone.Model
  idAttribute: "_id"
class Response extends Backbone.Model
  idAttribute: "_id"
class ResponseCollection extends Backbone.Collection
  model: Response
  comparator: (r) ->
    return (new Date(r.get("created")).getTime())


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
    fire.socket.send "firestarter/get_firestarter_list", {
      callback: "list_firestarters"
    }

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
          date = new intertwinkles.AutoUpdatingDate(date: doc.modified)
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
        "Firestarter URL: <br /><nobr>" +
        window.location.protocol + "//" + window.location.host + "/firestarter/f/" + val +
        "</nobr>"
      )
    else
      @$(".firestarter-url").html("")

  initializeURL: =>
    fire.socket.once "unused_slug", (data) =>
      @$("#id_slug").val(data.slug)
      @displayURL()
    fire.socket.send "firestarter/get_unused_slug", {
      callback: "unused_slug"
    }

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
          @$(".error")[0].scrollIntoView()
        else
          alert("Unexpected server error! Oh fiddlesticks!")
      else
        load_firestarter_data(data.model)
        fire.app.navigate("/firestarter/f/#{encodeURIComponent(fire.model.get("slug"))}", {trigger: true})
        $("html,body").animate({scrollTop: 0}, 0)

    fire.socket.send "firestarter/create_firestarter", {
      callback: "create_firestarter"
      model: {
        name: @$("#id_name").val()
        prompt: @$("#id_prompt").val()
        slug: @$("#id_slug").val()
        public: @$("#id_public").val()
        sharing: @sharing_control.sharing
      }
    }

class EditNameDialog extends intertwinkles.BaseModalFormView
  template: _.template $("#editNameDialogTemplate").html()

class EditPromptDialog extends intertwinkles.BaseModalFormView
  template: _.template $("#editPromptDialogTemplate").html()

class ShowFirestarter extends Backbone.View
  template: _.template $("#firestarterTemplate").html()
  events:
    'click #add_response': 'showAddResponseForm'
    'click .edit-name':    'editName'
    'click .edit-prompt':  'editPrompt'

  initialize: (options) ->
    if not fire.model? or fire.model.get("slug") != options.slug
      fire.model = new Firestarter()
      fire.responses = null
    if not fire.responses?
      fire.responses = new ResponseCollection()
    @responseViews = []

    @roomUsersMenu = new intertwinkles.RoomUsersMenu({
      room: "firestarter/" + options.slug
    })

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
      fire.socket.send "firestarter/get_firestarter", {slug: options.slug}

    # Reload sharing settings
    intertwinkles.user.on "change", @refreshFirestarter, this

  remove: =>
    @roomUsersMenu?.remove()
    @sharingButton?.remove()
    @editor?.remove()
    for view in @responseViews
      view.remove()
    fire.socket.stopListening("firestarter")
    fire.socket.stopListening("response")
    fire.socket.stopListening("delete_response")
    fire.model.off null, null, this
    intertwinkles.user.off null, null, this
    delete fire.model
    if fire.responses?
      delete fire.responses
    super()

  refreshFirestarter: =>
    for view in @responseViews
      view.remove()
    fire.socket.send "firestarter/get_firestarter", {slug: fire.model.get("slug")}

  editName: (event) =>
    event.preventDefault()
    form = new EditNameDialog(
      context: {name: fire.model.get("name")}
      validation: [["input[name=name]", ((v) -> v or null), "Please add a name.", "name"]]
    )
    form.render()
    form.$("input[name=name]").focus()
    form.on "submitted", (cleaned_data) =>
      if cleaned_data.name != fire.model.get("name")
        @editFirestarter({name: cleaned_data.name}, form.remove)
      else
        form.remove()

  editPrompt: (event) =>
    event.preventDefault()
    form = new EditPromptDialog(
      context: {prompt: fire.model.get("prompt")}
      validation: [["textarea", ((v) -> v or null), "Please add a prompting question.", "prompt"]]
    )
    form.render()
    form.$("textarea").focus()
    form.on "submitted", (cleaned_data) =>
      if cleaned_data.prompt != fire.model.get("prompt")
        @editFirestarter({prompt: cleaned_data.prompt}, form.remove)
      else
        form.remove()

  editFirestarter: (updates, cb) =>
    fire.socket.once 'firestarter_edited', (data) =>
      if data.error?
        flash "error", "Oh no!  Survur Urrur!"
        console.info(data.error)
      else
        fire.model.set(data.model)
      cb()
    fire.socket.send "firestarter/edit_firestarter", {
      callback: 'firestarter_edited'
      model: _.extend({
        _id: fire.model.get("_id")
      }, updates)
    }

  updateFirestarter: =>
    @$(".first-loading").hide()
    @$(".firestarter-name").html(_.escape(fire.model.get("name")))
    @$(".firestarter-prompt").html(intertwinkles.markup(fire.model.get("prompt")))
    @$(".firestarter-date").html(
      new Date(fire.model.get("created")).toString("htt dddd, MMMM dd, yyyy")
    )

  showAddResponseForm: (event) =>
    event.preventDefault()
    @editResponse(new Response())

  editResponse: (response) =>
    @editor = new EditResponseView(model: response)
    @editor.render()

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
      fire.socket.send "firestarter/delete_response", {
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
                content = "#{user?.name or event.data.action.name} responded (via #{via_user.name})."
              else
                content = "#{user?.name or event.data.action.name} responded."
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

      fire.socket.send "firestarter/get_firestarter_events", {
        callback: callback,
        firestarter_id: fire.model.id
      }

class EditResponseView extends intertwinkles.BaseModalFormView
  template: _.template $("#editResponseTemplate").html()

  initialize: (options={}) =>
    @model = options.model or new Response()
    super({
      context: _.extend({
          response: ""
          verb: if @model.get("_id") then "Save" else "Add"
        }, @model.toJSON())
      validation: [
        ["#id_user", ((v) -> v or null), "Please add a name.", "name"],
        ["#id_user_id", ((v) -> v or ""), "", "user_id"],
        ["textarea", ((v) -> v or null), "Please add a response.", "response"],
      ]
    })

  render: =>
    super()
    @addView("#name_controls", new intertwinkles.UserChoice(model: @model))
    @$("#id_user").focus()
    @on "submitted", (cleaned_data) ->
      updates = {
        _id: @model.get("_id")
        user_id: cleaned_data.user_id
        name: cleaned_data.name
        response: cleaned_data.response
        firestarter_id: fire.model.id
      }
      @$("input[type=submit]").addClass("loading")
      fire.socket.once "response_saved", (data) =>
        @remove()
        if data.error
          flash "error", "Oh noes. SERVER ERROR. !!"
          console.info data.error
        else
          add_it = not @model.get("_id")?
          @model.set(data.model)
          if add_it
            fire.responses.add(@model)
      fire.socket.send "firestarter/save_response", { callback: "response_saved", model: updates }

class DeleteResponseConfirmation extends intertwinkles.BaseModalFormView
  template: _.template $("#deleteResponseConfirmationTemplate").html()

class ShowResponseView extends Backbone.View
  template: _.template $("#responseTemplate").html()
  events:
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
    @date = new intertwinkles.AutoUpdatingDate(date: @response.get("created"))
    @$(".date-holder").html @date.el
    @date.render()
    @$el.effect("highlight", {}, 3000)

  confirmDelete: (event) =>
    event.preventDefault()
    form = new DeleteResponseConfirmation(context: @response.toJSON())
    form.render()
    form.on "submitted", =>
      @trigger "delete", @response
      form.remove()

  editResponse: (event) =>
    event.preventDefault()
    @trigger "edit", @response

class Router extends Backbone.Router
  routes:
    'firestarter/f/:room': 'room'
    'firestarter/new':     'newFirestarter'
    'firestarter/':        'index'

  onReconnect: -> # Override per view to handle reconnections.

  index: =>
    @view?.remove()
    @view = new SplashView()
    $("#app").html(@view.el)
    @view.render()
    @onReconnect = @index

  newFirestarter: =>
    @view?.remove()
    @view = new AddFirestarterView()
    $("#app").html(@view.el)
    @view.render()
    @onReconnect = (=>)

  room: (roomName) =>
    @view?.remove()
    slug = decodeURIComponent(roomName)

    @view = new ShowFirestarter({slug: slug})
    $("#app").html(@view.el)
    @view.render()
    @onReconnect = =>
      @view.roomUsersMenu.connect()
      fire.socket.send "firestarter/get_firestarter", {slug: fire.model.get("slug")}


fire.firestarter_url = (slug) ->
  return "#{INTERTWINKLES_APPS["firestarter"].url}/firestarter/f/#{slug}"

load_firestarter_data = (data) ->
  if not fire.responses?
    fire.responses = new ResponseCollection()
  if data.responses?
    while fire.responses.pop()
      null
    for response in data.responses
      fire.responses.add(new Response(_.extend({}, response)))
  if not fire.model?
    fire.model = new Firestarter()
  # Clone (shallow) the data object so we don't mess up the responses.
  fire_data = _.extend({}, data)
  fire_data.responses = (a._id for a in data.responses)
  fire.model.set(fire_data)

#
# Load initial data if any
#
if INITIAL_DATA.firestarter?
  load_firestarter_data(INITIAL_DATA.firestarter)

#
# GO!
#
intertwinkles.connect_socket ->
  intertwinkles.build_toolbar($("header"), {applabel: "firestarter"})
  intertwinkles.build_footer($("footer"))
  fire.socket = intertwinkles.socket

  unless fire.started == true
    fire.app = new Router()
    Backbone.history.start({pushState: true, hashChange: false})
    fire.started = true
    fire.socket.on "reconnected", ->
      fire.socket.once "identified", ->
        fire.app.onReconnect()
