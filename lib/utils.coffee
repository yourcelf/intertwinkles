###
This module defines a set of basic utilities for InterTwinkles' logic that
transcends multiple apps.

Permissions checks:
 - is_authenticated(session) - check if a session is authenticated
 - can_view(session, model) - check if the given session is authorized
   to view the model that has a standard InterTwinkles "sharing" property
 - can_edit(session, model) - check if the given session is authorized
   to edit the model that has a standard InterTwinkles "sharing" property
 - can_change_sharing(session, model) - check if the given session is
   authorized to change the sharing for the given model

Data prep for clients:
 - clean_sharing(session, model): return a modified version of the `sharing`
   properties for the given model which removes any email addresses the given
   session is not allowed to see.
 - list_public_documents(schema, session, callback): Return an array of 
   documents within the given mongoose schema which are "public".
 - list_group_documents(schema, session, callback): Return an array of
   documents within the given mongoose schema that belong to the session's
   groups.
 - list_accessible_documents(schema, session, callback): Return both
   public and group documents.
 - get_initial_data(session, config): Get the set of sanitized initial data
   for the client, including client-viewable configuration, groups, users,
   etc.

Other utils:
 - get_json(url, query, callback): Fetch json from the provided URL.
 - post_data(url, data, callback): Post json to the provided URL.
 - append_slash(express_app, route, methods=["get"]): Add a route
   to express which redirects to the same URL with an appended
   slash.  (e.g. redirect "/about" to "/about/").

###
_           = require 'underscore'
url         = require 'url'
http        = require 'http'
async       = require 'async'
https       = require 'https'
querystring = require 'querystring'

#
# Utilities
#
utils = {}
utils.slugify = (name) -> return name.toLowerCase().replace(/[^-a-z0-9]+/g, '-')
utils.absolutize_url = (base, given_url) ->
  if url.parse(given_url).protocol
    return given_url
  return base + given_url

# GET the resource residing at get_url with search query data `query`,
# interpreting the response as JSON.
utils.get_json = (get_url, query, callback) ->
  parsed_url = url.parse(get_url)
  httplib = if parsed_url.protocol == 'https:' then https else http
  opts = {
    hostname: parsed_url.hostname
    port: parseInt(parsed_url.port)
    path: "#{parsed_url.pathname}?#{querystring.stringify(query)}"
  }
  req = httplib.get(opts, (res) ->
    res.setEncoding('utf8')
    data = ''
    res.on 'data', (chunk) -> data += chunk
    res.on 'end', ->
      if res.statusCode != 200
        return callback {error: "Intertwinkles status #{res.statusCode}", msg: JSON.stringify(data)}
      try
        json = JSON.parse(data)
      catch e
        return callback {error: e}
      if json.error?
        callback(json)
      else
        callback(null, json)
  ).on("error", (e) -> callback(error: e))

utils.append_slash = (app, route, methods=["get"]) ->
  for method in methods
    app[method](
      new RegExp("^" + route + "$"),
      (req, res) -> res.redirect(req.path + "/")
    )

# Post the given data to the given URL as form encoded data; interpret the
# response as JSON.
utils.post_data = (post_url, data, callback, method='POST') ->
  unless callback?
    callback = (err, res) -> console.error(err) if err?
  post_url = url.parse(post_url)
  httplib = if post_url.protocol == 'https:' then https else http
  opts = {
    hostname: post_url.hostname
    port: parseInt(post_url.port)
    path: post_url.pathname
    method: method
  }
  req = httplib.request opts, (res) ->
    res.setEncoding('utf8')
    answer = ''
    res.on 'data', (chunk) -> answer += chunk
    res.on 'end', ->
      if res.statusCode == 200
        try
          json = JSON.parse(answer)
        catch e
          console.error e
          return callback {error: e}
        if json.error?
          callback(json)
        callback(null, json)
      else
        callback({error: "Intertwinkles status #{res.statusCode}", message: answer})
  data = JSON.stringify(data)
  req.setHeader("Content-Type", "application/json")
  req.setHeader("Content-Length", data.length)
  req.write(data)
  req.end()

# Return properties from an InterTwinkles app config that are safe for use in
# templates.
utils.clean_conf = (config) ->
  return {
    api_url: config.api_url
    apps: config.apps
    TESTING_MOCK_PERSONA: config.TESTING_MOCK_PERSONA
  }

utils.csv_escape = (str) ->
  str = str?.toString() or ""
  str = str.trim().replace(/"/g, '""')
  if (str.indexOf(",") != -1) or (str.indexOf("\n") != -1)
    str = '"' + str + '"'
  return str

utils.array_to_csv = (rows) ->
  return ((utils.csv_escape(r) for r in row).join(",") for row in rows).join("\n")

###############################################
# Session utilities
#


#
# Authorize a request originating from the browser with Mozilla persona and the
# InterTwinkles api server.
#

utils.is_authenticated = (session) -> return session?.auth?.email?

utils.get_initial_data = (session, config) ->
  initial_data = {
    email: session?.auth?.email or null
    groups: session?.groups or {}
    users: session?.users or {}
    anon_id: session?.anon_id
    time: new Date().getTime()
  }
  if config.alpha_cookie_domain
    initial_data.ALPHA_COOKIE_DOMAIN = config.alpha_cookie_domain
  return initial_data

#
# Permissions. Expects 'session' to have auth and groups params as populated by
# 'verify' above, and model to have the following schema:
#   sharing: {
#     group_id: String          -- a group ID from InterTwinkles
#     public_view_until: Date   -- Date until expiry of public viewing. Set to 
#                                  far future for perpetual public viewing.
#     public_edit_until: Date   -- Date until expiry of public editing. Set to 
#                                  far future for perpetual public viewing.
#     extra_viewers: [String]   -- A list of email addresses of people who are
#                                  also allowed to view.
#     extra_editors: [String]   -- A list of email addresses of people who are
#                                  also allowed to edit.
#     advertise: Boolean        -- List/index this document publicly?
#   }
#
#  Assumptions: Edit permissions imply view permissions.  Group association
#  implies all permissions granted to members of that group. Absence of group
#  association implies the public can view and edit (e.g. etherpad style;
#  relies on secret URL for security).
#
#  If a document is owned (e.g. has a group, or explicit extra_editors), only
#  owners (group members or explicit editors) can change sharing options.
#
utils.can_view = (session, model) ->
  # Editing implies viewing.
  return true if utils.can_edit(session, model)
  # Is this public for viewing but not editing?
  return true if model.sharing?.public_view_until > new Date()
  # Are we specifically listed as an extra viewer?
  return true if (
    model.sharing?.extra_viewers? and
    session.auth?.email? and
    model.sharing.extra_viewers.indexOf(session.auth.email) != -1
  )
  return false

utils.can_edit = (session, model) ->
  # No group? Everyone can edit.
  return true if not model.sharing?.group_id?
  # If it is associated with a group, it might be marked public.
  return true if model.sharing?.public_edit_until > new Date()
  # Otherwise, we have to be signed in.
  return false if not session.auth?.email?
  # Or we could be in a group that owns this.
  return true if _.find(session.groups, (g) -> "" + g.id == "" + model.sharing?.group_id)
  # Or marked as specifically allowed to edit
  return true if (
    model.sharing?.extra_editors? and
    session.auth?.email? and
    model.sharing.extra_editors.indexOf(session.auth.email) != -1
  )
  return false

utils.can_change_sharing = (session, model) ->
  # Doesn't belong to a group, go ahead.
  return true if not model.sharing?.group_id? and (
    (model.sharing?.extra_editors or []).length == 0
  )
  # Doc belongs to a group.  Must be logged in.
  return false unless session?.auth?.email
  # All good if you belong to the group.
  return true if session?.groups?[model.sharing.group_id]?
  # All good if you are an explicit extra editor
  return true if _.find(model.sharing?.extra_editors or [], session.auth.email)
  return false

# Return a copy of the sharing properties of this model which do not contain
# email addresses or any other details the given user session shouldn't see. 
# The main rub: sharing settings might specify a list of email addresses of
# people who can edit or view. But a doc might also be made public for a period
# of time.  If it is public, and we aren't in the group or in the list of
# approved editors/viewers, hide email addresses.
utils.clean_sharing = (session, model) ->
  return {} if not model.sharing?
  cleaned = {
    group_id: model.sharing.group_id
    public_view_until: model.sharing.public_view_until
    public_edit_until: model.sharing.public_edit_until
    advertise: model.sharing.advertise
  }
  # If we aren't signed in (or there are no specified 'extra_viewers' or
  # 'extra_editors' to show), don't return any extra viewers or extra editors.
  return cleaned if not session?.auth?.email? or not (model.sharing.extra_viewers? or model.sharing.extra_editors?)
  # If we're in the group, or in the list of approved viewers/editors, show the
  # addresses.
  email = session.auth.email
  group = session.groups?[model.sharing.group_id]
  if (group? or
      model.sharing.extra_editors?.indexOf(email) != -1 or
      model.sharing.extra_viewers?.indexOf(email) != -1)
    cleaned.extra_editors = (e for e in model.sharing.extra_editors or [])
    cleaned.extra_viewers = (e for e in model.sharing.extra_viewers or [])
  return cleaned

utils.update_sharing = (model, sharing) ->
  model.sharing ?= {}
  for key in ["public_edit_until", "public_view_until", "advertise", "group_id"]
    model.sharing[key] = sharing[key]
  model.sharing.extra_editors = sharing.extra_editors or []
  model.sharing.extra_viewers = sharing.extra_viewers or []

utils.sharing_is_equal = (s1, s2) ->
  if !!s1.advertise != !!s2.advertise
    return false
  if s1.group_id or s2.group_id
    return false if s1.group_id?.toString() != s2.group_id?.toString()
  for key in ["public_view_until", "public_edit_until"]
    if s1[key] or s2[key]
      d1 = new Date(s1[key])
      d2 = new Date(s2[key])
      now = new Date().getTime()
      d1_far_future = d1.getTime() - now > 50 * 365 * 24 * 60 * 60 * 1000
      d2_far_future = d2.getTime() - now > 50 * 365 * 24 * 60 * 60 * 1000
      if (!d1_far_future or !d2_far_future) and (d1.getTime() != d2.getTime())
        return false
  for key in ["extra_viewers", "extra_editors"]
    if s1[key] or s2[key]
      l1 = s1[key]?.length or 0
      l2 = s2[key]?.length or 0
      return false if l1 != l2
      return false if _.union(s1[key] or [], s2[key] or []).length != l1
  return true


# List all the documents in `schema` (a Mongo/Mongoose collection) which are
# currently public.  Use for providing a dashboard listing of documents.
utils.list_public_documents = (schema, session, cb, condition={}, sort="modified", skip=0, limit=20, clean=true) ->
  # Find the public documents.
  query = _.extend({
    "sharing.advertise": true
    $or: [
      { "sharing.group_id": null },
      { "sharing.public_edit_until": { $gt: new Date() }}
      { "sharing.public_view_until": { $gt: new Date() }}
    ]
  }, condition)
  schema.find(query).sort(sort).skip(skip).limit(limit).exec (err, docs) ->
    return cb(err) if err?
    if clean
      for doc in docs
        doc.sharing = utils.clean_sharing(session, doc)
    cb(null, docs)

# List all the documents in `schema` (a Mongo/Mongoose collection) which belong
# to the given session.  Use for providing a dashboard listing of documents.
utils.list_group_documents = (schema, session, cb, condition={}, sort="modified", skip=0, limit=20, clean=true) ->
  # Find the group documents
  if not session?.auth?.email?
    cb(null, []) # Not signed in; we have no group docs.
  else
    query = _.extend({
      $or: [
        {"sharing.group_id": { $in : (id for id,g of session.groups or []) }}
        {"sharing.extra_editors": session.auth.email}
        {"sharing.extra_viewers": session.auth.email}
      ]
    }, condition)
    schema.find(query).sort(sort).skip(skip).limit(limit).exec (err, docs) ->
      return cb(err) if err?
      if clean
        for doc in docs
          doc.sharing = utils.clean_sharing(session, doc)
      cb(null, docs)

# List both public and group documents, in an object {public: [docs], group: [docs]}
utils.list_accessible_documents = (schema, session, cb, condition={}, sort="modified", skip=0, limit=20, clean=true) ->
  async.series [
    (done) -> utils.list_group_documents(schema, session, done, condition, sort, skip, limit, clean)
    (done) -> utils.list_public_documents(schema, session, done, condition, sort, skip, limit, clean)
  ], (err, res) ->
    cb(err, { group: res[0], public: res[1] })

module.exports = utils
