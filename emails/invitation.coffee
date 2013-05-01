_ = require "underscore"
base = require "./base"

sms = _.template("InterTwinkles! Invitation to join <%= group.name %>: <%= short_url %>")

subject = _.template("Invitation to <%= group.name %> on InterTwinkles")

text = _.template("""
<%= recipient.name %>,

<%= sender ? sender.name + " (" + sender.email + ") invited you" : "You've been invited" %> to join "<%= group.name %>" at InterTwinkles!  

You were invited as <b><%- recipient.email %></b>. Sign in using that address to accept or decline this invitation.

You can accept or decline the invitation here:
<%= url %>
""".trim())

html = _.template("""
<p><%- recipient.name %>, </p>
<p>
  <% if (sender) { %>
    <%- sender.name %>
    <% if (sender.email) { %>
      (<a href='mailto:<%- sender.email %>'><%- sender.email %></a>)
    <% } %>
    invited you
  <% } else { %>
    You've been invited
  <% } %>
  to join <b><%- group.name %></b> at InterTwinkles!
</p>
<p>
  You were invited as <strong><%- recipient.email %></strong>. Sign in using that
  address to accept or decline this invitation.
</p>
<p><a href='<%- url %>'>Accept or Decline the invitation</a></p>
""".trim())

web = _.template("""
You've been invited to join <%- group.name %>! Please accept
or refuse the invitation.
""".trim())

module.exports = {
  web: web
  sms: (context) -> return sms(context)
  email: {
    subject: (context) ->
      context.subject = subject(context)
      return base.email.subject(context)

    text: (context) ->
      context.body = text(context)
      return base.email.text(context)

    html: (context) ->
      context.body = html(context)
      return base.email.html(context)
  }
}
