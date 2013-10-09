path = require "path"

route = (config, app, sockrooms) ->
  schema = require('./schema').load(config)

  app.get "/hangout/gadget.xml", (req, res) ->
    file_path = path.resolve(__dirname + "/../builtAssets/hangout.xml")
    res.sendfile(file_path)

  app.get "/hangout/", (req, res) ->
    # Handle Cross-document messages from within google hangouts.
    res.send("todo")

module.exports = {route}

