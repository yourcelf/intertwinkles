###
A SockJS client that works with express cookies and our room server to
initialize identification.

The client may be in one of many states, which are referenced as @state, and
triggered when the client enters that state.  The naming follows
SockJS.readyState's state naming, with the addition of 'identifying' and
'identified':
 - connecting: we're trying to establish the socket connection.
 - open: We have a socket connection, but haven't identified.
 - identifying: We're working on identifying using the session ID obtained from
   the express.sid cookie.
 - identified: We're identified. From now on, we should be able to send any app messages.
 - closing: We're working on shutting down the socket connection.
 - closed: The socket connection is closed.

On construction, the client tries to identify.  Probably best to listen for
"identified" to indicate that we have a working socket connection.

Takes a single 'url' argument in the constructor, which is where we should find
the sockjs server to connect to.  Default "/sockjs".

Uses Backbone.Events for event triggering.
###

class intertwinkles.SocketClient
  _.extend @prototype, Backbone.Events
  # Preserve state numbering
  CONNECTING: SockJS.CONNECTING
  OPEN: SockJS.OPEN
  IDENTIFYING: 4
  IDENTIFIED: 5
  CLOSING: SockJS.CLOSING
  CLOSED: SockJS.CLOSED

  constructor: (url) ->
    @state = @CLOSED
    @connect(url)

  connect: (url="/sockjs") =>
    if @state == @CLOSED
      @trigger "connecting", this
      @state = @CONNECTING
      @sock = new SockJS(url)
      @sock.onopen = @_onOpen
      @sock.onmessage = @_onMessage
      @sock.onclose = @_onClose
      return true
    return false

  disconnect: =>
    if @sock.readyState == @CONNECTING or @sock.readyState == @OPEN
      @trigger "closing", this
      @state = @CLOSING
      @sock.close()
      @sock.onopen = @sock.onmessage = @sock.onclose = null
    @state = @CLOSED
    @trigger "closed", this

  reconnect: =>
    @disconnect()
    @connect()

  identify: =>
    @state = @IDENTIFYING
    @send "identify", {session_id: $.cookie("express.sid")}

  isIdentified: =>
    return @state == @IDENTIFIED

  isAlive: =>
    return not @isFinished()

  isFinished: =>
    return @state == @CLOSING or @state == @CLOSED

  send: (route, data) =>
    data ?= {}
    @sock.send JSON.stringify({
      route: route
      body: data
    })

  _onOpen: =>
    @state = @OPEN
    @identify()
    @trigger "open", this

  _onMessage: (event) =>
    data = JSON.parse(event.data)
    { route, body } = data

    if route == "identify"
      @state = @IDENTIFIED
      @session_id = body.session_id
      @trigger "identified", this
    else if route == "error"
      # XXX Replace this with a more reasonable error handler.
      flash "error", "Server errored. Oh noes!"
      console.log "error:", body.error
    else
      @trigger route, body

  _onClose: =>
    @disconnect()

intertwinkles.connect_socket = (cb) ->
  if intertwinkles.socket? and intertwinkles.socket.isAlive()
    if cb?
      if intertwinkles.socket.isIdentified()
        cb(intertwinkles.socket)
      else
        intertwinkles.socket.on "identified", cb
  else
    socket = new intertwinkles.SocketClient("/sockjs")
    #TODO: Link with UI to indicate state of connection / loss of connection.
    socket.on "identified", ->
      intertwinkles.socket = socket
      cb?(intertwinkles.socket)
