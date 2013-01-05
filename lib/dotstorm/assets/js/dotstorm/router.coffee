class ds.Router extends Backbone.Router
  routes:
    'd/:slug/add/':      'dotstormAddIdea'
    'd/:slug/edit/:id/': 'dotstormEditIdea'
    'd/:slug/tag/:tag/': 'dotstormShowTag'
    'd/:slug/:id/':      'dotstormShowIdeas'
    'd/:slug/':          'dotstormShowIdeas'
    '':                  'intro'

  intro: ->
    ds.leaveRoom()
    intro = new ds.Intro()
    intro.on "open", (slug, name) =>
      @open slug, name, =>
        @navigate "/d/#{slug}/"
        @dotstormShowIdeas(slug)
    $("#app").html intro.el
    intro.render()

  dotstormShowIdeas: (slug, id, tag) =>
    @open slug, "", =>
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
    @open slug, "", ->
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
    @open slug, "", ->
      idea = ds.ideas.get(id)
      if not idea?
        flash "error", "Idea not found.  Check the URL?"
      else
        # Re-fetch to pull in deferred fields.
        idea.fetch
          success: (idea) =>
            view = new ds.EditIdea(idea: idea, dotstorm: ds.model)
            $("#app").html view.el
            view.render()
    return false

  open: (slug, name, callback) =>
    # Open (if it exists) or create a new dotstorm with the name `name`, and
    # navigate to its view.
    return callback() if ds.model?.get("slug") == slug

    fixLinks = ->
      $("nav a.show-ideas").attr("href", "/d/#{slug}/")
      $("nav a.add").attr("href", "/d/#{slug}/add")
      $("a.dotstorm-read-only-link").attr("href", "/e/#{ds.model.get("embed_slug")}")

    if (not ds.model?) and INITIAL_DATA.dotstorm?.slug == slug
      ds.ideas = new ds.IdeaList()
      for idea in INITIAL_DATA.ideas
        ds.ideas.add new ds.Idea(idea)
      ds.model = new ds.Dotstorm(INITIAL_DATA.dotstorm)
      fixLinks()
      ds.joinRoom(ds.model)
      callback?()
    else
      # Fetch the ideas.
      coll = new ds.DotstormList
      coll.fetch
        query: { slug }
        success: (coll) ->
          ds.ideas = new ds.IdeaList()
          if coll.length == 0
            ds.model = new ds.Dotstorm()
            ds.model.save { name, slug },
              success: (model) ->
                flash "info", "Created!  Click things to change them."
                ds.joinRoom(model)
                fixLinks()
                callback()
              error: (model, err) ->
                console.log "error", err
                flash "error", err
          else if coll.length == 1
            ds.model = coll.models[0]
            fixLinks()
            ds.joinRoom(coll.models[0])
            ds.ideas.fetch
              error: (coll, err) ->
                console.log "error", err
                flash "error", "Error fetching #{attr}."
              success: (coll) -> callback?()
              query: {dotstorm_id: ds.model.id}
              fields: {drawing: 0}
        error: (coll, res) =>
          console.log "error", res
          flash "error", res.error
      return false

room_view = null
sharing_view = null
ds.leaveRoom = ->
  room_view?.remove()
  sharing_view?.remove()
  $(".dotstorm-read-only-link").hide()

ds.joinRoom = (newModel) ->
  ds.leaveRoom()

  room_view = new intertwinkles.RoomUsersMenu(room: newModel.id)
  $(".sharing-online-group .room-users").replaceWith(room_view.el)
  room_view.render()

  sharing_view = new intertwinkles.SharingSettingsButton(model: newModel)
  $(".sharing-online-group .sharing").html(sharing_view.el)
  sharing_view.render()
  sharing_view.on "save", (sharing_settings) =>
    ds.model.save {sharing: sharing_settings}, {
      error: (model, err) =>
        console.info(err)
        flash "error", "Server error!"
        ds.model.set(model)
    }
    sharing_view.close()

  $(".dotstorm-read-only-link").show()
