intertwinkles.connect_socket = (cb) ->
  socket = io.connect("/io-intertwinkles")
  socket.on "error", (data) ->
    flash "error", "Intertwinkles server error.  So sorry!"
    window.console?.log?(data.error)
  socket.on "connect", ->
    intertwinkles.socket = socket
    intertwinkles.socket_connected = true
    cb?(socket)
  socket.on "disconnect", ->
    intertwinkles.socket_connected = false
