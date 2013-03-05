# 
# Socket data!!!!!!!!!!!!!!
#
intertwinkles.connect_socket (socket) ->
  intertwinkles.build_toolbar($("header"), {applabel: "dotstorm"})
  intertwinkles.build_footer($("footer"))
  ds.socket = socket
  Backbone.setSocket(ds.socket)
  # Re-fetch models if we get disconnected.
  ds.socket.on "reconnected", ->
    ds.socket.once "identified", ->
      console.log "re-fetching..."
      if ds.model?
        ds.model.fetch {
          query: {_id: ds.model.id}
          success: (model) -> console.log "re-fetched", model
        }
      if ds.ideas?
        ds.ideas.fetch {
          query: {dotstorm_id: ds.model.id}
          fields: drawing: 0
          success: (coll) -> console.log "re-fetched", coll
        }
      if ds.room_view?
        ds.room_view.connect()

  ds.app = new ds.Router
  Backbone.history.start pushState: true

  intertwinkles.twunklify("#app")
  intertwinkles.modalvidify("#app")

  ds.socket.on 'dotstorm/backbone', (data) ->
    console.debug 'backbone sync', data
    switch data.signature.collectionName
      when "Idea"
        switch data.signature.method
          when "create"
            ds.ideas.add(new ds.Idea(data.model))
          when "update"
            model = ds.ideas.get(data.model.id)
            if model?
              model.set(data.model)
            else
              ds.ideas.fetch({
                query: {dotstorm_id: ds.model.id}
                fields: {drawing: 0}
              })
          when "delete"
            model = ds.ideas.get(data.model._id)
            if model?
              ds.ideas.remove(model)
            else
              ds.ideas.fetch({
                query: {dotstorm_id: ds.model.id}
                fields: drawing: 0
              })

      when "Dotstorm"
        switch data.signature.method
          when "update"
            ds.model.set data.model

    ds.socket.on 'dotstorm/trigger', (data) ->
      #console.debug 'trigger', data
      switch data.collectionName
        when "Idea"
          ds.ideas.get(data.id).trigger data.event

window.addEventListener 'message', (event) ->
  if event.origin == "file://"
    if event.data.cameraEnabled?
      ds.cameraEnabled = true
    else if event.data.error?
      flash "info", event.data.error
    else if event.data.reload?
      flash "info", "Reloading..."
      window.location.reload(true)
, false

$("a.soft").on 'touchend click', (event) ->
  ds.app.navigate $(event.currentTarget).attr('href'), trigger: true
  return false
