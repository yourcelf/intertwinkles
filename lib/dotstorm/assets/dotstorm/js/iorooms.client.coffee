class Client
  constructor: (socket) ->
    @socket = socket

  join:  (room) => @socket.emit 'join', room: room
  leave: (room) => @socket.emit 'leave', room: room
  setName: (name) => @socket.emit 'username', name: name

if typeof exports != "undefined"
  exports.Client = Client
else
  this.Client = Client
