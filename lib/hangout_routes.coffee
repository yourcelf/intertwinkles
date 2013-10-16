path  = require "path"
_     = require "underscore"
http  = require "http"
utils = require './utils'

hangout_rooms = {}

route = (config, app, sockrooms) ->
  schema = require('./schema').load(config)
  www_methods = require("./www_methods")(config)
  hangout_methods = require('./hangout_methods')(config)

  broadcastRoomDocs = (room, socket, session) ->
    docs = hangout_rooms[room]?.docs
    if docs
      cleaned = hangout_methods.clean_room_docs(session, docs)
    else
      cleaned = []
    socket.sendJSON "hangout:document_list", {hangout_docs: cleaned}

  sockrooms.addChannelAuth "hangout", (session, room, callback) ->
    # No authorization required for joining hangout
    [channel, name] = room.split("/")
    return callback(null, channel == "hangout")

  sockrooms.on "leave", (data) ->
    {socket, session, room, last} = data
    [channel, name] = room.split("/")
    if channel == "hangout"
      sockrooms.getSessionsInRoom room, (err, sessions) ->
        if sessions.length == 0
          delete hangout_rooms[room]

  sockrooms.on "join", (data) ->
    {socket, session, room, first} = data
    [channel, name_stub] = room.split("/")
    if channel == "hangout"
      hangout_rooms[room] ?= {docs: []}
      broadcastRoomDocs(room, socket, session)

  sockrooms.on "hangout/add_document", (socket, session, data) ->
    respond = (err, docs) ->
      return sockrooms.handleError(socket, err) if err?
      sockrooms.roomSocketSessionMap data.room, (err, sock, sess) ->
        return sockrooms.handleError(sock, err) if err?
        broadcastRoomDocs(data.room, sock, sess)
    return respond("Room not found") unless hangout_rooms[data.room]?
    return respond("Missing URL") unless data.request_url?

    current = hangout_rooms[data.room].docs

    # Try adding anew.
    hangout_methods.validate_url session, data.request_url, (err, urlinfo) ->
      return respond(err, null) if err?
      return respond("Bad URL", null) unless urlinfo.doc?
      # Is it already added?
      if _.findWhere(current, (d) -> d.id == urlinfo.doc.id)?
        # If it is, just send the current list to the requester.
        return broadcastRoomDocs(data.room, socket, session)
      else
        # It's new. Add it, and broadcast to everyone.
        current.push(urlinfo.doc)
        return respond(null, current)

  sockrooms.on "hangout/list_room_documents", (socket, session, data) ->
    broadcastRoomDocs(data.room, socket, session)

  sockrooms.on "hangout/list_user_documents", (socket, session, data) ->
    respond = (err, docs) ->
      return sockrooms.handleError(socket, err) if err?
      socket.sendJSON "hangout:user_documents", {docs}

    utils.list_group_documents(
      schema.SearchIndex, session, respond, {trash: {$ne: true}}, "-modified", 0, 0, true
    )

  sockrooms.on "hangout/validate_url", (socket, session, data) ->
    hangout_methods.validate_url session, data.request_url, (err, urlinfo) ->
      return sockrooms.handleError(socket, err) if err?
      ret = {request_url: urlinfo.request_url, valid: urlinfo.valid}
      if urlinfo.doc?
        clean = urlinfo.doc.toJSON()
        clean.sharing = utils.clean_sharing(session, urlinfo.doc.sharing)
        ret.doc = clean
      socket.sendJSON "hangout:validate_url", ret

  context = (req, jade_context, initial_data) ->
    return _.extend({
      initial_data: _.extend(
        {application: "www"},
        utils.get_initial_data(req?.session, config),
        initial_data or {}
      )
      conf: utils.clean_conf(config)
      flash: req.flash(),
    }, jade_context)


  app.get "/hangout/gadget.xml", (req, res) ->
    res.setHeader('Content-Type', 'application/xml')
    render_context = {
      intertwinkles_origin: config.api_url
      hangout_iframe_src: config.api_url + "/hangout/"
      testurl: false
    }
    if process.env.NODE_ENV != "production"
      render_context.testurl = res.query?.testurl or "test"
    res.render "hangout/gadget", render_context

  app.get "/hangout/", (req, res) ->
    res.render "hangout/index", context(req, {}, {
      hangout_origin: config.hangout_origin
      intertwinkles_url_base: config.api_url
      intertwinkles_short_url_base: config.short_url_base
    })

  app.get "/hangout/test/gadget_contents/", (req, res) ->
    libxmljs = require "libxmljs"
    http.get config.api_url + "/hangout/gadget.xml", (xml_res) ->
      data = ''
      xml_res.on 'data', (chunk) -> data += chunk
      xml_res.on 'end', ->
        xml = libxmljs.parseXml(data)
        content = xml.get('//Content').text()
        res.send content
    .on 'error', (err) ->
      return www_methods.handle_error(req, res, err) if err?

  app.get "/hangout/test/", (req, res) ->
    res.render "hangout/test"

module.exports = {route}

