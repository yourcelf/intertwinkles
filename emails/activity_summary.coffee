_    = require 'underscore'
base = require './base'
jade = require 'jade'
fs   = require 'fs'

sms_template = _.template([
  'Recent InterTwinkles activity: ',
  '<%- todos ? todos + " TODO" + (todos != 1 ? "s" : "") + ((edits || visits) ? ", " : "") : "" %>',
  '<%- edits ? edits + " edit" + (edits != 1 ? "s" : "") + (visits ? ", " : "") : "" %>',
  '<%- visits ? visits + " visit" + (visits != 1 ? "s" : "") : "" %>',
].join(""))

subject_template = _.template([
  "Activity summary: ",
  '<%- todos ? todos + " TODO" + (todos != 1 ? "s" : "") + ((edits || visits) ? ", " : "") : "" %>',
  '<%- edits ? edits + " edit" + (edits != 1 ? "s" : "") + (visits ? ", " : "") : "" %>',
  '<%- visits ? visits + " visit" + (visits != 1 ? "s" : "") : "" %>',
].join(""))

text_email_template = _.template("""
<% if (recipient.name) { %><%= recipient.name %>,
 
<% } %>Activity summary on InterTwinkles for <%- start.toDateString() %>:

View full details<%- todos ? " and respond" : "" %> here:
<%- show_url %>/


""" + [
  '<% if (todos) { %>',
    "- TODOs: Your response is needed for <%- todos %>",
      " thing", '<%- todos == 1 ? "" : "s" %>\n'
  '<% } %>',
  '<% if (edits) { %>',
    "- <%- edits %> thing", '<%- edits == 1 ? "" : "s" %>',
      " edited in your groups\n",
  '<% } %>',
  '<% if (visits) { %>'
    "- <%- visits %> thing", '<%- visits == 1 ? "" : "s" %>',
      " visited in your groups\n",
  '<% } %>',
].join("") + """
""")

_path = __dirname + "/../views/home/includes/activity.jade"
html_email_template = jade.compile(fs.readFileSync(_path, 'utf8'), {
  filename: _path, pretty: true
})

module.exports = {
  sms: (context) ->
    rendered = sms_template(context)
    if rendered.length + context.short_url.length + 1 > 160
      # Make space for short URL and ellipsis
      rendered = rendered.substring(
        0, rendered.length - context.short_url.length - 1 - 3
      )
      rendered += "... " + context.short_url
    else
      rendered += " " + context.short_url
    return rendered

  email: {
    subject: (context) ->
      context.subject = subject_template(context)
      return base.email.subject_template(context)

    text: (context) ->
      context.body = text_email_template(context)
      return base.email.text_template(context)

    html: (context) ->
      context.body = html_email_template(context)
      return base.email.html_template(context)
  }
}
