class ds.Router extends Backbone.Router
  routes:
    'dotstorm/d/:slug/add/':      'dotstormAddIdea'
    'dotstorm/d/:slug/edit/:id/': 'dotstormEditIdea'
    'dotstorm/d/:slug/tag/:tag/': 'dotstormShowTag'
    'dotstorm/d/:slug/:id/':      'dotstormShowIdeas'
    'dotstorm/d/:slug/':          'dotstormShowIdeas'
    'dotstorm/new/':              'newDotstorm'
    'dotstorm/':                  'intro'

  intro: ->
    ds.leaveRoom()
    intro = new ds.Intro()
    intro.on "open", (slug, name) =>
      @open slug, name, =>
        @navigate "/dotstorm/d/#{slug}/"
        @dotstormShowIdeas(slug)
    $("#app").html intro.el
    intro.render()

  newDotstorm: =>
    view = new ds.EditDotstorm()
    view.on "save", (model) =>
      ds.model = model
      ds.ideas = new ds.IdeaList()
      @navigate "/dotstorm/d/#{model.get("slug")}/", {trigger: true}
    $("#app").html view.el
    view.render()

  dotstormShowIdeas: (slug, id, tag) =>
    @open slug, =>
      $("#app").html new ds.Organizer({
        model: ds.model
        ideas: ds.ideas
        showId: id
        showTag: tag
      }).render().el
    return false

  dotstormShowTag: (slug, tag) =>
    @dotstormShowIdeas(slug, null, tag)

  dotstormAddIdea: (slug) =>
    @open slug, ->
      view = new ds.EditIdea
        idea: new ds.Idea
        dotstorm: ds.model
        cameraEnabled: ds.cameraEnabled
      if ds.cameraEnabled
        view.on "takePhoto", =>
          flash "info", "Calling camera..."
          handleImage = (event) ->
            if event.origin == "file://" and event.data.image?
              view.setPhoto(event.data.image)
            window.removeEventListener "message", handleImage, false
          window.addEventListener 'message', handleImage, false
          window.parent.postMessage('camera', 'file://')
      $("#app").html view.el
      view.render()
    return false

  dotstormEditIdea: (slug, id) =>
    @open slug, ->
      idea = ds.ideas.get(id)
      if not idea?
        flash "error", "Idea not found.  Check the URL?"
      else
        # Re-fetch to pull in deferred fields.
        idea.fetch {
          success: (idea) =>
            view = new ds.EditIdea(idea: idea, dotstorm: ds.model)
            $("#app").html view.el
            view.render()
        }
    return false

  open: (slug, callback) =>
    return callback() if ds.model?.get("slug") == slug

    fixLinks = ->
      $("a.dotstorm-read-only-link").attr("href", "/dotstorm/e/#{ds.model.get("embed_slug")}")

    if (not ds.model?) and INITIAL_DATA.dotstorm?.slug == slug
      ds.ideas = new ds.IdeaList()
      for idea in INITIAL_DATA.ideas
        ds.ideas.add new ds.Idea(idea)
      ds.model = new ds.Dotstorm(INITIAL_DATA.dotstorm)
      fixLinks()
      ds.joinRoom(ds.model)
      callback()
    else
      fixLinks()

    return false

ds.room_view = null
ds.sharing_view = null
ds.leaveRoom = ->
  ds.room_view?.remove()
  ds.sharing_view?.remove()
  $(".dotstorm-read-only-link").hide()
  ds.room_view = null
  ds.sharing_view = null

ds.joinRoom = (newModel) ->
  ds.leaveRoom()

  ds.room_view = new intertwinkles.RoomUsersMenu(room: "dotstorm/" + newModel.id)
  $(".sharing-online-group .room-users").replaceWith(ds.room_view.el)
  ds.room_view.render()

  ds.sharing_view = new intertwinkles.SharingSettingsButton(model: newModel)
  $(".sharing-online-group .sharing").html(ds.sharing_view.el)
  ds.sharing_view.render()
  ds.sharing_view.on "save", (sharing_settings) =>
    ds.model.save {sharing: sharing_settings}, {
      error: (model, err) =>
        console.info(err)
        flash "error", "Server error!"
        ds.model.set(model)
    }
    ds.sharing_view.close()

  $(".dotstorm-read-only-link").show()
