_    = require "underscore"
base = require "../../../emails/base"

sms = _.template("Your response needed to a <%= group.name %> proposal: <%= short_url %>: ")
subject = _.template("<%= group.name %> proposal, your response needed")
text = _.template("""
<%= recipient.name %>,

<%= sender ? sender.name + " added a proposal" : "A new proposal was added" %> in <%= group.name %> on InterTwinkles.  Your response is needed:

<%= url %>

----

"<%- proposal.revisions[0].text %>"
""".trim())

html = _.template("""
<p><%- recipient.name %>, </p>
<p>
  <% if (sender) { %>
    <%- sender.name %> added a proposal
  <% } else { %>
    A new proposal was added
  <% } %>
  in <b><%- group.name %></b> on <a href='<%- home_url %>'>InterTwinkles</a>.
</p>

<p><a href='<%- url %>'>Your response is needed!</a></p>

<p><b>Current revision:</b></p>

<p><%- proposal.revisions[0].text %></p>

""".trim())

web = _.template("""<b><%- group.name %></b> needs your response to a proposal""")

module.exports = {
  web: web
#  sms: (context) ->
#    proposal = context.proposal
#    prefix = sms(context)
#    prop_text = proposal.revisions[0].text
#    if prop_text.length + prefix < 160
#      return prefix + prop_text
#    else
#      return prefix + prop_text.substring(0, 160 - 3 - prefix.length) + "..."
#
#  email: {
#    subject: (context) ->
#      context.subject = subject(context)
#      return base.email.subject(context)
#
#    text: (context) ->
#      context.body = text(context)
#      return base.email.text(context)
#
#    html: (context) ->
#      context.body = html(context)
#      return base.email.html(context)
#  }
}
