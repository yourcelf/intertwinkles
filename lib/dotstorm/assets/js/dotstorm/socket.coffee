# 
# Socket data!!!!!!!!!!!!!!
#
intertwinkles.socket = ds.socket = io.connect("/iorooms", reconnect: false)
Backbone.setSocket(ds.socket)
ds.app = new ds.Router
ds.socket.on 'connect', ->
  ds.client = new Client(ds.socket)
  Backbone.history.start pushState: true

  ds.socket.on 'backbone', (data) ->
    console.debug 'backbone sync', data
    switch data.signature.collectionName
      when "Idea"
        switch data.signature.method
          when "create"
            ds.ideas.add(new ds.Idea(data.model))
          when "update"
            model = ds.ideas.get(data.model._id)
            if model?
              model.set(data.model)
            else
              ds.ideas.fetch({fields: drawing: 0})
          when "delete"
            model = ds.ideas.get(data.model._id)
            if model?
              ds.ideas.remove(model)
            else
              ds.ideas.fetch({fields: drawing: 0})

      when "Dotstorm"
        switch data.signature.method
          when "update"
            ds.model.set data.model

  ds.socket.on 'trigger', (data) ->
    #console.debug 'trigger', data
    switch data.collectionName
      when "Idea"
        ds.ideas.get(data.id).trigger data.event

ds.socket.on 'disconnect', ->
  # Timeout prevents a flash when you are just closing a tab.
  setTimeout ->
    flash "error", "Connection lost.  <a href='' onclick='window.location.reload(); return false;'>Click to reconnect</a>."
  , 1000

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
