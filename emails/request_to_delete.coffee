_ = require "underscore"

module.exports = {
  web: _.template("""
    <%- sender.name %> has asked to delete <b><%- deletion_request.title %></b> permanently. Please confirm or cancel; it will be automatically deleted <tt class='varsub' data-date='<%- deletion_request.end_date.getTime() %>'><%- deletion_request.end_date.toString() %></tt>.
  """)
}
