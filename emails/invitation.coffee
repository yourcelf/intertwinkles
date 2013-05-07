_ = require "underscore"
base = require "./base"

sms_template = _.template("InterTwinkles! Invitation to join <%= group.name %>: <%= short_url %>")

subject_template = _.template("Invitation to <%= group.name %> on InterTwinkles")

text_template = _.template("""
<% if (recipient.name) { %>
<%= recipient.name %>,

<% } %><%= sender ? sender.name + " (" + sender.email + ") invited you" : "You've been invited" %> to join "<%= group.name %>" at InterTwinkles!  

You were invited as <%- recipient.email %>. Sign in using that address to accept or decline this invitation.

You can accept or decline the invitation here:
<%= url %>
""".trim())

html_template = _.template("""
<% if (recipient.name) { %>
<p><%- recipient.name %>, </p>
<% } %>
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

web_template = _.template("""
You've been invited to join <%- group.name %>! Please accept
or refuse the invitation.
""".trim())

module.exports = {
  web: web_template
  sms: (context) -> return sms_template(context)
  email: {
    subject: (context) ->
      context.subject = subject_template(context)
      return base.email.subject_template(context)

    text: (context) ->
      context.body = text_template(context)
      return base.email.text_template(context)

    html: (context) ->
      context.body = html_template(context)
      return base.email.html_template(context)
  }
}
