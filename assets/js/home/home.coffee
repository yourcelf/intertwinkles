invite_view_template = """
  <% for (var i = 0; i < invites.length; i++) { %>
    <div class='alert invitation' data-url='<%- invites[i].url %>' style='cursor: pointer;'>
      <table>
        <tr>
          <td class='invitor'>
            <%= intertwinkles.inline_user(invites[i].sender) %>
          </td>
          <td class='invitation'>
            <%- invites[i].formats.web %>
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

intertwinkles.sub_vars()
