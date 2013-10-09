class intertwinkles.User extends Backbone.Model
  idAttribute: "id"

#
# API methods
#

# Request logout
intertwinkles.request_logout = ->
  navigator.id.logout()

# Request login
intertwinkles.request_login = ->
  opts = {
    siteName: "InterTwinkles"
    returnTo: "/"
  }
  if window.location.protocol == "https:"
    opts.termsOfService = "/about/terms/"
    opts.privacyPolicy = "/about/privacy/"
    opts.siteLogo = "/static/img/star-icon.png"
  navigator.id.request(opts)

# Check for authentication state
intertwinkles.is_authenticated = ->
  return intertwinkles.user.get("email")?

# Refresh maps of users and groups.
intertwinkles.refresh_session = ->
  return if window.INTERTWINKLES_AUTH_LOGOUT
  if not intertwinkles.socket?
    console.info "refresh_session awaiting socket"
    intertwinkles.SOCKET_TIMEOUT_COUNT += 1
    if intertwinkles.SOCKET_TIMEOUT_COUNT > 100
      console.error "Socket fail; can't handle refresh_session request"
      return
    return setTimeout(intertwinkles.refresh_session, 100)
  console.info "refresh session"
  intertwinkles.socket.once "groups", (data) ->
    intertwinkles.users = data.users
    intertwinkles.groups = data.groups
    intertwinkles.user.set(_.find(intertwinkles.users, (e) -> e.email == data.email))
  intertwinkles.socket.send("refresh_session")

#
# Set up User authentication state
#
do ->
  #console.info "load initial data"
  # Load initial data.
  intertwinkles.user = new intertwinkles.User()
  intertwinkles.users = null  # map of intertwinkles user_id to user data
  intertwinkles.groups = null # list of groups
  if INITIAL_DATA.groups?
    intertwinkles.groups = INITIAL_DATA.groups
  if INITIAL_DATA.users?
    intertwinkles.users = INITIAL_DATA.users
    user = _.find intertwinkles.users, (e) -> e.email == INITIAL_DATA.email
    if user? then intertwinkles.user.set(user)
  # Refresuh users/groups.
  if intertwinkles.is_authenticated()
    intertwinkles.refresh_session()

#
# Persona handlers
#

# On login handler
intertwinkles.SOCKET_TIMEOUT_COUNT = 0
intertwinkles._onlogin = (assertion) ->
  if window.INTERTWINKLES_AUTH_LOGOUT?
    return intertwinkles.request_logout()

  if not intertwinkles.socket?
    console.info "onlogin awaiting socket"
    intertwinkles.SOCKET_TIMEOUT_COUNT += 1
    if intertwinkles.SOCKET_TIMEOUT_COUNT > 100
      console.error "Socket fail; can't handle onlogin request."
      return
    return setTimeout((-> intertwinkles._onlogin(assertion)), 100)

  console.info "onlogin"

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
          # don't trigger user changed yet -- we want to edit the profile first.
          intertwinkles.user.set(user, silent: true)
        else
          # triggers user changed.
          intertwinkles.user.set(user)
      else
        intertwinkles.user.clear()

      if data.message == "NEW_ACCOUNT" or user?.name == ""
        profile_editor = new intertwinkles.EditNewProfile()
        $("body").append(profile_editor.el)
        profile_editor.render()
        profile_editor.on "done", finish
      else if old_user != intertwinkles.user.get("email")
        flash "info", "Welcome, #{intertwinkles.user.get("name")}"
        finish()

    if data.error?
      intertwinkles.request_logout()
      flash "error", data.error or "Error signing in."

  intertwinkles.socket.once "login", handle
  intertwinkles.socket.send "verify", {callback: "login", assertion: assertion}
  intertwinkles.socket.on "force_logout", -> navigator.id.logout()

# On logout handler
intertwinkles._onlogout = (count) ->
  intertwinkles.users = null
  intertwinkles.groups = null
  if not intertwinkles.socket?
    if count > 200
      console.error("Socket connection failed.")
      return
    count ?= 0
    console.info "onlogout awaiting socket #{count}..."
    return setTimeout( ->
      intertwinkles._onlogout(count + 1)
    , 100)
  console.info "onlogout"
  intertwinkles.socket.once "logout", ->
    reload = intertwinkles.is_authenticated()
    intertwinkles.user.clear()
    intertwinkles.user.trigger("logout")
    if reload or window.INTERTWINKLES_AUTH_LOGOUT
      flash "info", "Signed out."
      window.location.pathname = window.INTERTWINKLES_AUTH_LOGOUT_REDIRECT or "/"
  intertwinkles.socket.send "logout", {callback: "logout"}

# Set up watch.
navigator.id.watch({
  loggedInUser: intertwinkles.user.get("email") or null
  onlogin: intertwinkles._onlogin
  onlogout: intertwinkles._onlogout
})
