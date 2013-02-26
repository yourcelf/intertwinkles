# adapted from
# http://developer.teradata.com/blog/jasonstrimpel/2011/11/backbone-js-and-socket-io
  
Backbone.setSocket = (socket) -> Backbone._socket = socket
Backbone.getSocket = -> Backbone._socket

Backbone.sync = (method, model, options) ->
  #console.log method, model, options
  unless Backbone._socket?
    options.error "No socket connection" if options.error
    return
  socket = Backbone._socket

  # Create a signature identifying to the server what we intend to do
  signature = {
    collectionName: model.collectionName
    method: method
    isCollection: model instanceof Backbone.Collection
    query: options.query
    fields: options.fields
  }
  
  # Create a response event name to use once, if we have a success callback to
  # respond with.
  if options.success? or options.error?
    event = "dotstorm/" + [model.collectionName, method, Math.random()].join(":")
    socket.once event, (data) ->
      if data.error
        options.error(model, data, {}) if options.error?
      else
        options.success(model, data, {}) if options.success?
    signature.event = event

  # Send our stuff.
  socket.send 'dotstorm/backbone', {
    signature: signature
    model: model.toJSON()
  }
