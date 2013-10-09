expect        = require 'expect.js'
_             = require 'underscore'
async         = require 'async'
common        = require '../../../test/common'
config        = require '../../../test/test_config'
api_methods   = require('../../../lib/api_methods')(config)

describe "Socket dotstorms", ->
  @timeout(20000)
  server = null
  session = {}
  client = null

  before (done) ->
    common.startUp (theserver) ->
      server = theserver
      async.series [
        (done) ->
          # Establish a session.
          common.identifiedSockjsClient server, session, "one@mockmyid.com", (theclient) ->
            client = theclient
            done()
      ], done

  after (done) ->
    client.close()
    common.shutDown(server, done)


  dotstorm = null
  idea = null

  it "creates a dotstorm", (done) ->
    client.writeJSON {
      route: "dotstorm/create_dotstorm"
      body: {dotstorm: {name: "My Dotstorm", slug: "my-dotstorm"}}
    }
    client.onceJSON (data) ->
      expect(data.route).to.be("dotstorm:dotstorm")
      expect(data.body.dotstorm._id).to.not.be(null)
      expect(data.body.dotstorm.name).to.be("My Dotstorm")
      expect(data.body.dotstorm.slug).to.be("my-dotstorm")
      dotstorm = data.body.dotstorm


      client.writeJSON {
        route: "join"
        body: {room: "dotstorm/#{dotstorm._id}"}
      }
      client.onceJSON (data) ->
        expect(data.route).to.be("join")
        done()

  it "edits a dotstorm", (done) ->
    client.writeJSON {
      route: "dotstorm/edit_dotstorm"
      body: {dotstorm: {_id: dotstorm._id, name: "Your Dotstorm"}}
    }
    client.onceJSON (data) ->
      expect(data.route).to.be("dotstorm:dotstorm")
      expect(data.body.dotstorm._id).to.eql(dotstorm._id)
      expect(data.body.dotstorm.name).to.be("Your Dotstorm")
      expect(data.body.dotstorm.slug).to.be("my-dotstorm")
      dotstorm = data.body.dotstorm
      done()

  it "creates an idea", (done) ->
    i = 0
    mkIdea = (description, done) ->
      client.writeJSON {
        route: "dotstorm/create_idea"
        body: {
          dotstorm: {_id: dotstorm._id}
          idea: {description: description}
        }
      }
      client.onceJSON (data) ->
        expect(data.route).to.be("dotstorm:ideas")
        expect(data.body.ideas.length).to.be(1)
        expect(data.body.ideas[0].description).to.be(description)
        idea = data.body.ideas[0]
        client.onceJSON (data) ->
          expect(data.route).to.be("dotstorm:dotstorm")
          expect(data.body.dotstorm._id).to.eql(dotstorm._id)
          expect(data.body.dotstorm.groups.length).to.be(i + 1)
          expect(data.body.dotstorm.groups[0].ideas.length).to.be(1)
          expect(data.body.dotstorm.groups[0].ideas[0]).to.eql(idea._id)
          dotstorm = data.body.dotstorm
          i += 1
          done()
    async.mapSeries ["woot", "right on"], mkIdea, (err) -> done(err)

  it "edits an idea", (done) ->
    client.writeJSON {
      route: "dotstorm/edit_idea"
      body: {idea: {
        _id: idea._id
        description: "Fer Shore"
        drawing: [["pencil", 0, 0, 640, 640]]
      }}
    }
    client.onceJSON (data) ->
      expect(data.route).to.be("dotstorm:ideas")
      expect(data.body.ideas.length).to.be(1)
      expect(data.body.ideas[0].description).to.be("Fer Shore")
      idea = data.body.ideas[0]
      done()

  it "rearranges notes", (done) ->
    client.writeJSON {
      route: "dotstorm/rearrange"
      body: {
        dotstorm: {_id: dotstorm._id, groups: dotstorm.groups, trash: dotstorm.trash}
        movement: [0, 0, 1, 0, 0]
      }
    }
    client.onceJSON (data) ->
      expect(data.route).to.be("dotstorm:dotstorm")
      expect(data.body.dotstorm._id).to.eql(dotstorm._id)
      expect(data.body.dotstorm.groups.length).to.be(1)
      expect(data.body.dotstorm.groups[0].ideas.length).to.be(2)
      dotstorm = data.body.dotstorm
      done()

  it "edits a group label", (done) ->
    client.writeJSON {
      route: "dotstorm/edit_group_label"
      body: {
        dotstorm: {_id: dotstorm._id}
        group: {_id: dotstorm.groups[0]._id, label: "For Shizzle"}
      }
    }
    client.onceJSON (data) ->
      expect(data.route).to.be("dotstorm:dotstorm")
      expect(data.body.dotstorm._id).to.eql(dotstorm._id)
      expect(data.body.dotstorm.groups[0].label).to.be("For Shizzle")
      dotstorm = data.body.dotstorm
      done()

  it "fetches an idea", (done) ->
    client.writeJSON {
      route: 'dotstorm/get_idea'
      body: {idea: {_id: idea._id}}
    }
    client.onceJSON (data) ->
      expect(data.route).to.be("dotstorm:ideas")
      expect(data.body.ideas.length).to.be(1)
      expect(data.body.ideas[0].drawing.length).to.be(1)
      expect(data.body.ideas[0].drawing[0]).to.eql(["pencil", 0, 0, 640, 640])
      done()

  it "fetches a dotstorm", (done) ->
    client.writeJSON {
      route: "dotstorm/get_dotstorm",
      body: {dotstorm: {slug: "my-dotstorm"}}
    }
    client.onceJSON (data) ->
      expect(data.route).to.be("dotstorm:ideas")
      expect(data.body.ideas.length).to.be(2)
      for idea in data.body.ideas
        expect(idea.drawing).to.be(undefined)
      client.onceJSON (data) ->
        expect(data.route).to.be("dotstorm:dotstorm")
        expect(data.body.dotstorm.id).to.eql(dotstorm.id)
        done()

