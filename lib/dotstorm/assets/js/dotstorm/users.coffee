
class ds.UsersView extends Backbone.View
  template: _.template $("#usersWidget").html() or ""
  events:
    'mousedown .users': 'toggle'
    'touchstart .users': 'toggle'
    'keyup .you input': 'changeName'

  initialize: (options) ->
    @self = options.users.self
    @users = options.users.others
    @open = false
    @url = options.url

  render: =>
    userlist = _.reject (u for i,u of @users), (u) => u.user_id == @self.user_id
    @$el.html @template
      self: @self
      users: userlist
      open: @open
      url: @url
      embed_slug: ds.model.get("embed_slug")
    this

  toggle: (event) =>
    @open = not @open
    @render()
    return false

  changeName: (event) =>
    @self.name = $(event.currentTarget).val()
    if @updateTimeout?
      clearTimeout @updateTimeout
    @updateTimeout = setTimeout =>
      ds.client.setName @self.name
    , 500
    return false

  removeUser: (user) =>
    delete @users[user.user_id]
    @render()

  addUser: (user) =>
    if user.user_id != @self.user_id
      @users[user.user_id] = user
    @render()

  setUser: (user) =>
    @users[user.user_id] = user
    @render()
