notification_menu_template = _.template("""
  <a href='#'
     class='dropdown-toggle notification-trigger<%- notices.length > 0 ? " unread" : "" %>'
     data-toggle='dropdown'
     role='button'><%- notices.length > 50 ? "50+" : notices.length %></a>
  <ul class='notifications dropdown-menu' role='menu'>
    <li class='linkless'><h3>Your Action Needed</h3></li>
    <% for (var i = 0; i < notices.length; i++) { %>
      <% var notice = notices[i]; %>
      <li class='notification <%- notice.read ? "read" : "" %>'>
        <a href='<%- notice.absolute_url %>' data-notification-id='<%- notice._id %>'>
          <div class='sender'>
            <% var sender = intertwinkles.users[notice.sender]; %>
            <% if (sender) { %>
              <img src='<%- sender.icon.small %>' /> <%- sender.name %>:
            <% } %>
          </div>
          <div class='message'>
            <div class='body'><%- notice.formats.web %></div>
            <div class='byline'><span class='date' data-date='<%- notice.date %>'></span></div>
          </div>
        </a>
      </li>
    <% } %>
    <li class='linkless'></li>
  </ul>
""")

class Notification extends Backbone.Model
  idAttribute: '_id'
class NotificationCollection extends Backbone.Collection
  model: Notification

class intertwinkles.NotificationMenu extends Backbone.View
  tagName: 'li'
  template: notification_menu_template
  events:
    'click .notification-trigger': 'openMenu'

  initialize: ->
    @notices = new NotificationCollection()
    @dateViews = []
    @open = false
    interval = setInterval =>
      if intertwinkles.socket?
        intertwinkles.socket.on "notifications", @handleNotifications
        @fetchNotifications()
        clearInterval(interval)
    , 100
    intertwinkles.user.on "login", @fetchNotifications
    intertwinkles.user.on "logout", @fetchNotifications

  remove: =>
    intertwinkles.socket.off "notifications", @handleNotifications
    intertwinkles.user.off "change", @fetchNotifications
    view.remove() for view in @dateViews
    super()

  fetchNotifications: =>
    if intertwinkles.is_authenticated()
      @notices = new NotificationCollection()
      intertwinkles.socket.send "get_notifications" # should result in 'render'
    else
      @render() # just nuke 'em!

  handleNotifications: (data) =>
    for notification in data.notifications
      found = @notices.get(notification._id)
      # Remove notifications that come as "cleared" or "suppressed"
      if notification.cleared or notification.suppressed
        if found?
          @notices.remove(found)
      else if found
        found.set(notification)
      else
        @notices.add(new Notification(notification))
    @render()

  render: =>
    view.remove() for view in @dateViews
    notices = (n.toJSON() for n in @notices.models)
    if intertwinkles.is_authenticated() and @notices.length > 0
      @$el.addClass("notification-menu dropdown").html(@template {
        open: @open
        notices: notices
      })

      @dateViews = []
      @$(".date").each (i, el) =>
        view = new intertwinkles.AutoUpdatingDate(date: $(el).attr("data-date"))
        @dateViews.push(view)
        $(el).html view.render().el
    else
      @$el.html("")
    this

  openMenu: =>
    #@open = not @open
    #@render()
    #return false
