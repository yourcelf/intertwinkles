#
# Dotstorm router
#

class ds.Router extends Backbone.Router
  routes:
    'dotstorm/d/:slug/add/':      'addIdea'
    'dotstorm/d/:slug/edit/:id/': 'editIdea'
    'dotstorm/d/:slug/tag/:tag/': 'organizerTag'
    'dotstorm/d/:slug/:id/':      'organizer'
    'dotstorm/d/:slug/':          'organizer'
    'dotstorm/new/':              'newDotstorm'
    'dotstorm/':                  'intro'

  initialize: ->
    # Set a persistent dotstorm model and ideas collection, which we clear or
    # load as needed.
    @dotstorm = new ds.Dotstorm(INITIAL_DATA.dotstorm or {})
    @ideas = new ds.IdeaList()
    @ideas.reset(new ds.Idea(idea) for idea in INITIAL_DATA.ideas or [])

    # Listeners persist as long as this router is active.  Rely on @joinRoom or
    # @leaveRoom to prevent receiving data at the wrong time.
    @listenTo intertwinkles.socket, "dotstorm:ideas", @ideas.load
    @listenTo intertwinkles.socket, "dotstorm:dotstorm", @dotstorm.load

  _check_slug: (slug, callback) =>
    if @dotstorm?.get("slug") == slug
      room = "dotstorm/" + @dotstorm.id
      console.log room
      @joinRoom(@dotstorm) unless @room_view?.room == room
      return callback()
    else
      @leaveRoom()
      @dotstorm.clear()
      @ideas.reset()
      intertwinkles.socket.send "dotstorm/get_dotstorm", {dotstorm: {slug: slug}}
      @dotstorm.once "load", =>
        @joinRoom(@dotstorm)
        callback()

  _display: (view) =>
    @view?.remove()
    @view = view
    $("#app").html(view.el)
    view.render()

  intro: =>
    @leaveRoom()
    @dotstorm.clear()
    @ideas.reset()
    @_display(new ds.Intro())

  newDotstorm: =>
    @leaveRoom()
    @dotstorm.clear()
    @ideas.reset()
    @_display(new ds.EditDotstorm({dotstorm: @dotstorm}))

  organizer: (slug, id, tag) =>
    @_check_slug slug, =>
      @_display(new ds.Organizer({
        dotstorm: @dotstorm
        ideas: @ideas
        showId: id
        showTag: tag
      }))

  organizerTag: (slug, tag) =>
    @dotstormOrganizer(slug, null, tag)

  addIdea: (slug) =>
    @_check_slug slug, =>
      @_display(new ds.EditIdea({idea: new ds.Idea, dotstorm: @dotstorm, ideas: @ideas}))

  editIdea: (slug, id) =>
    @_check_slug slug, =>
      idea = @ideas.get(id)
      if not idea?
        flash "error", "Idea not found.  Check the URL?"
      else
        # Re-fetch to pull in deferred fields.
        intertwinkles.socket.send "dotstorm/get_idea", {idea: {_id: id}}
        idea.once "load", =>
          @_display(new ds.EditIdea({idea: idea, dotstorm: @dotstorm, ideas: @ideas}))

  #
  # Room management
  #

  leaveRoom: =>
    @room_view?.remove()
    @sharing_view?.remove()
    $(".dotstorm-read-only-link").hide()
    @room_view = null
    @sharing_view = null

  joinRoom: (newModel) =>
    @room_view = new intertwinkles.RoomUsersMenu(room: "dotstorm/" + newModel.id)
    $(".sharing-online-group .room-users").replaceWith(@room_view.el)
    @room_view.render()

    @sharing_view = new intertwinkles.SharingSettingsButton({
      model: newModel
      application: "dotstorm"
    })
    $(".sharing-online-group .sharing").html(@sharing_view.el)
    @sharing_view.render()
    @sharing_view.on "save", (sharing_settings) =>
      intertwinkles.socket.send "dotstorm/edit_dotstorm", {
        dotstorm: {_id: @dotstorm.id, sharing: sharing_settings}
      }
      @dotstorm.once "load", =>
        @sharing_view.close()
    $("a.dotstorm-read-only-link").show().attr(
      "href", "/dotstorm/e/#{newModel.get("embed_slug")}"
    )

intertwinkles.connect_socket (socket) ->
  intertwinkles.build_toolbar($("header"), {applabel: "dotstorm"})
  intertwinkles.build_footer($("footer"))

  ds.app = intertwinkles.app = new ds.Router
  Backbone.history.start pushState: true, hashChange: false

  # Re-fetch models if we get disconnected.
  intertwinkles.socket.on "reconnected", ->
    intertwinkles.socket.once "identified", ->
      console.log "re-fetching..."
      if ds.app.room_view?
        ds.app.room_view.connect()
      if ds.app.dotstorm.id
        intertwinkles.socket.send "dotstorm/get_dotstorm", {
          dotstorm: {_id: ds.app.dotstorm.id}
        }
