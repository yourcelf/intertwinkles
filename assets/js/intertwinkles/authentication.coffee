class intertwinkles.User extends Backbone.Model
  idAttribute: "id"

#
# User authentication state
#
intertwinkles.user = new intertwinkles.User()
intertwinkles.users = null  # map of intertwinkles user_id to user data
intertwinkles.groups = null # list of groups
if INITIAL_DATA.groups?
  intertwinkles.groups = INITIAL_DATA.groups
if INITIAL_DATA.users?
  intertwinkles.users = INITIAL_DATA.users
  user = _.find intertwinkles.users, (e) -> e.email == INITIAL_DATA.email
  if user? then intertwinkles.user.set(user)

#
# Persona handlers
#

intertwinkles.request_logout = ->
  frame = $("#auth_frame")[0].contentWindow
  frame.postMessage {action: 'intertwinkles_logout'}, INTERTWINKLES_API_URL

intertwinkles.onlogin = (assertion) ->
  console.log "onlogin"
  if window.INTERTWINKLES_AUTH_LOGOUT?
    return intertwinkles.request_logout()

  finish = ->
    intertwinkles.user.trigger("login")
    if window.INTERTWINKLES_AUTH_REDIRECT?
      window.location.href = INTERTWINKLES_AUTH_REDIRECT

  handle = (data) ->
    old_user = intertwinkles.user?.get("email")
    if not data.error? and data.email
      intertwinkles.users = data.users
      intertwinkles.groups = data.groups
      user = _.find intertwinkles.users, (e) -> e.email == data.email
      if user?
        if data.message == "NEW_ACCOUNT" or user.name == ""
          intertwinkles.user.set(user, silent: true)
        else
          intertwinkles.user.set(user)
      else
        intertwinkles.user.clear()

      if data.message == "NEW_ACCOUNT" or user?.name == ""
        profile_editor = new intertwinkles.EditNewProfile()
        $("body").append(profile_editor.el)
        profile_editor.render()
      else if old_user != intertwinkles.user.get("email")
        flash "info", "Welcome, #{intertwinkles.user.get("name")}"
        finish()

    if data.error?
      intertwinkles.request_logout()
      flash "error", data.error or "Error signing in."

  if intertwinkles.socket?
    if intertwinkles.socket.isIdentified()
      intertwinkles.socket.once "login", handle
      intertwinkles.socket.send "verify", {callback: "login", assertion: assertion}
    else
      if confirm("Lost connection. Refresh page?")
        window.location.href = window.location.href
  else
    alert("Error: socket missing")

intertwinkles.onlogout = ->
  console.log "onlogout"
  intertwinkles.users = null
  intertwinkles.groups = null
  if intertwinkles.socket?
    intertwinkles.socket.once "logout", ->
      reload = intertwinkles.is_authenticated()
      intertwinkles.user.clear()
      intertwinkles.user.trigger("logout")
      if reload or window.INTERTWINKLES_AUTH_LOGOUT
        flash "info", "Signed out."
        window.location.pathname = "/"
    intertwinkles.socket.send "logout", {callback: "logout"}
  else
    alert("Socket connection failed")

onmessage = (event) ->
  if event.origin == INTERTWINKLES_API_URL
    switch event.data.action
      when 'onlogin' then intertwinkles.onlogin(event.data.assertion)
      when 'onlogout' then intertwinkles.onlogout()
window.addEventListener('message', onmessage, false)

intertwinkles.is_authenticated = -> return intertwinkles.user.get("email")?

intertwinkles.auth_frame_template = _.template("""<iframe id='auth_frame'
  src='#{INTERTWINKLES_API_URL}/static/auth_frame.html'
  style='border: none; overflow: hidden;' width=97 height=29></iframe>""")

