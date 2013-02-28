invite_view_template = """
  <% for (var i = 0; i < invites.length; i++) { %>
    <div class='alert invitation' data-url='<%= invites[i].url %>' style='cursor: pointer;'>
      <table>
        <tr>
          <td class='invitor'>
            <%- intertwinkles.inline_user(invites[i].sender) %>
          </td>
          <td class='invitation'>
            <%= invites[i].formats.web %>
          </td>
        </tr>
      </table>
    </div>
  <% } %>
"""
class InviteView extends Backbone.View
  template: _.template(invite_view_template)
  events:
    'click .invitation': 'gothere'
  initialize: (options) ->
    @invites = options?.invites or []
  render: =>
    if @invites.length > 0
      @$el.hide()
      @$el.html(@template(invites: @invites))
      @$el.slideDown()
    else
      @$el.html("")
  gothere: (event) =>
    url = $(event.currentTarget).attr("data-url")
    window.location.href = url if url

intertwinkles.connect_socket ->
  invite_view = new InviteView()
  # Must call this before we build the header, and request notifications.
  intertwinkles.socket.on "notifications", (data) ->
    invites = []
    for notice in data.notifications
      if notice.application == "www" and notice.type == "invitation"
        invites.push(notice)
    invite_view.invites = invites
    $(".getting-started-invitations").html(invite_view.el)
    invite_view.render()

  intertwinkles.build_toolbar($("header"), {applabel: "home"})
  intertwinkles.build_footer($("footer"))


sub_vars = (scope=document) ->
  $(".varsub", scope).each ->
    $el = $(this)

    #
    # Dashboard fill-ins
    #
    if $el.attr("data-date")
      date = new intertwinkles.AutoUpdatingDate(date: $el.attr("data-date"))
      $el.html(date.el)
      date.render()

    else if $el.attr("data-group-id")
      group = intertwinkles.groups[$el.attr("data-group-id")]
      if not group?
        $el.hide()
      else
        $el.show().html(group.name)

    else if $el.attr("data-user-id")
      user = intertwinkles.users[$el.attr("data-user-id")]
      if user?
        $el.html "<img src='#{user.icon.tiny}' /> #{user.name}"
      else
        $el.html "<i class='icon-user'></i> (protected)"

  $(".markmeup", scope).each ->
    $(this).html(intertwinkles.markup($(this).html()))

  $(".tile-link").on "click", (event) ->
    href = $("a", event.currentTarget).attr("href")
    if href
      window.location.href = href

sub_vars()
window.sub_vars = sub_vars
