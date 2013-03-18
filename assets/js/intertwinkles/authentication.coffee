class intertwinkles.User extends Backbone.Model
  idAttribute: "id"

#
# User authentication state
#
intertwinkles.load_initial_data = ->
  console.log "load initial data"
  intertwinkles.user = new intertwinkles.User()
  intertwinkles.users = null  # map of intertwinkles user_id to user data
  intertwinkles.groups = null # list of groups
  if INITIAL_DATA.groups?
    intertwinkles.groups = INITIAL_DATA.groups
  if INITIAL_DATA.users?
    intertwinkles.users = INITIAL_DATA.users
    user = _.find intertwinkles.users, (e) -> e.email == INITIAL_DATA.email
    if user? then intertwinkles.user.set(user)
intertwinkles.load_initial_data()

#
# Persona handlers
#

intertwinkles.request_logout = ->
  navigator.id.logout()

intertwinkles.request_login = ->
  opts = {
    siteName: "InterTwinkles"
    termsOfService: "/about/terms/"
    privacyPolicy: "/about/privacy/"
    returnTo: "/"
  }
  if window.location.protocol == "https:"
    opts.siteLogo = "/static/img/star-icon.png"
  navigator.id.request(opts)


intertwinkles.onlogin = (assertion) ->
  if window.INTERTWINKLES_AUTH_LOGOUT?
    return intertwinkles.request_logout()

  if not intertwinkles.socket?
    console.log "onlogin awaiting socket"
    return setTimeout((-> intertwinkles.onlogin(assertion)), 100)

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

intertwinkles.onlogout = (count) ->
  intertwinkles.users = null
  intertwinkles.groups = null
  if not intertwinkles.socket?
    if count > 200
      console.error("Socket connection failed.")
      return
    count ?= 0
    #console.info "onlogout awaiting socket #{count}..."
    return setTimeout( ->
      intertwinkles.onlogout(count + 1)
    , 100)
  console.info "onlogout"
  intertwinkles.socket.once "logout", ->
    reload = intertwinkles.is_authenticated()
    intertwinkles.user.clear()
    intertwinkles.user.trigger("logout")
    if reload or window.INTERTWINKLES_AUTH_LOGOUT
      flash "info", "Signed out."
      window.location.pathname = "/"
  intertwinkles.socket.send "logout", {callback: "logout"}

intertwinkles.is_authenticated = -> return intertwinkles.user.get("email")?

navigator.id.watch({
  onlogin: intertwinkles.onlogin
  onlogout: intertwinkles.onlogout
})
