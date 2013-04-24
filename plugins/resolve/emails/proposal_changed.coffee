_    = require "underscore"
base = require "../../../emails/base"

sms = _.template("A <%= group.name %> proposal changed, please confirm your vote. <%= short_url %>: ")
subject = _.template("<%= group.name %> proposal changed, please confirm your vote")
text = _.template("""
<%= recipient.name %>,

<%= sender.name %> changed a proposal that you had already voted on in <%= group.name %> on InterTwinkles.  Please confirm your vote:

<%= url %>

----

"<%- proposal.revisions[0].text %>"
""".trim())

html = _.template("""
<p><%- recipient.name %>, </p>
<p>

  <%- sender.name %> changed a proposal that you had already voted on in
  <b><%- group.name %></b> on <a href='<%- home_url %>'>InterTwinkles</a>.
</p>

<p><a href='<%- url %>'>Please confirm your vote</a>.</p>

<p><b>Current revision:</b></p>

<p><%- proposal.revisions[0].text %></p>

""".trim())

web = _.template("""<b><%- group.name %></b> proposal has changed;
                    please confirm your vote.""")

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
