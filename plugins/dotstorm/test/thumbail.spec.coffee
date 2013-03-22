fs         = require 'fs'
expect     = require 'expect.js'
config     = require '../../../test/test_config'
models     = require('../lib/schema').load(config)
common     = require '../../../test/common'

describe "Dotstorm Canvas to image from idea", ->
  before (done) ->
    @mahId = undefined
    common.startUp (server) =>
      @server = server
      done()

  after (done) ->
    common.shutDown(@server, done)

  it "creates idea", (done) ->
    idea = new models.Idea
      dotstorm_id: "aaaaaaaaaaaaaaaaaaaaaaaa"
      background: "#ffffdd"
      tags: "ok"
      description: "whatevs"
      drawing: [["pencil", 0, 0, 400, 400]]

    idea.save (err) =>
      @mahId = idea._id
      expect(err).to.be null
      expect(fs.existsSync idea.getDrawingPath("small")).to.be true
      done()
      return true

  it "removes the idea", (done) ->
    models.Idea.findOne {_id: @mahId}, (err, idea) ->
      expect(err).to.be null
      expect(idea).to.not.be null
      idea.remove (err) ->
        expect(fs.existsSync idea.getDrawingPath("small")).to.be false
        done()
