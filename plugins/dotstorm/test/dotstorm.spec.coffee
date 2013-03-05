expect       = require 'expect.js'
uuid         = require 'node-uuid'

# Hack to get client code into node.
coffee       = require 'coffee-script'
fs           = require 'fs'
_            = require 'underscore'
Backbone     = require 'backbone'
clientModels = ds = {}
eval(coffee.compile(fs.readFileSync(__dirname + "/../assets/dotstorm/js/models.coffee").toString()))


describe "Dotstorm idea reordering", ->
  dotstorm = new clientModels.Dotstorm slug: 'test'
  # idea IDs
  a = 'a'
  b = 'b'
  c = 'c'
  d = 'd'
  # Create a group
  g = (ids...) -> return {_id: uuid.v4(), ideas: ids}

  # Ensure groups are equal, excluding group ID's, which are random.
  expectMatch = (map2) ->
    map1 = dotstorm.get("groups")
    expect(map1.length).to.be map2.length
    for i in [0...map1.length]
      expect(map1[i].ideas).to.eql map2[i].ideas

  it "generates a UUID", -> expect(dotstorm.uuid().length).to.be 36
  it "expects the right matches", ->
    dotstorm.set "groups", [g(a)]
    expectMatch [g(a)]
    expect(-> expectMatch [g(b)]).to.throwError()
    expect(-> expectMatch [g(a,b)]).to.throwError()

  it "adds ideas", ->
    dotstorm.addIdea(new clientModels.Idea(_id: a))
    expectMatch [g(a)]
    # Should be idempotent
    dotstorm.addIdea(new clientModels.Idea(_id: a))
    expectMatch [g(a)]

  it "removes ideas", ->
    dotstorm.removeIdea(new clientModels.Idea(_id: a))
    expectMatch []
    # Should be idempotent
    dotstorm.removeIdea(new clientModels.Idea(_id: a))
    expectMatch []

  it "moves idea adjacent group, left side", ->
    dotstorm.set "groups", [g(a), g(b), g(c)]
    dotstorm.move(0, 0, 2, null) # move a adjacent c
    expectMatch [g(b), g(a), g(c)]
    dotstorm.move(2, 0, 0, null) # move c adjacent b
    expectMatch [g(c), g(b), g(a)]

  it "moves idea adjacent group, right side", ->
    dotstorm.set "groups", [g(a), g(b), g(c)]
    dotstorm.move(0, 0, 2, null, 1)
    expectMatch [g(b), g(c), g(a)]
    dotstorm.move(2, 0, 0, null, 1)
    expectMatch [g(b), g(a), g(c)]

  it "moves idea out of group, left side", ->
    dotstorm.set "groups", [g(a, b), g(c, d)]
    dotstorm.move(0, 0, 1, null)
    expectMatch [g(b), g(a), g(c, d)]

  it "moves idea out of group, right side", ->
    dotstorm.set "groups", [g(a, b), g(c, d)]
    dotstorm.move(0, 0, 1, null, 1)
    expectMatch [g(b), g(c, d), g(a)]

  it "moves idea within group, left side", ->
    dotstorm.set "groups", [g(a, b, c), g(d)]
    dotstorm.move(0, 0, 0, 1)
    expectMatch [g(a, b, c), g(d)]
    dotstorm.move(0, 0, 0, 2)
    expectMatch [g(b, a, c), g(d)]

  it "moves idea within group, right side", ->
    dotstorm.set "groups", [g(a, b, c), g(d)]
    dotstorm.move(0, 0, 0, 1, 1)
    expectMatch [g(b, a, c), g(d)]
    dotstorm.move(0, 0, 0, 2, 1)
    expectMatch [g(a, c, b), g(d)]

  it "moves group adjacent group, left side", ->
    dotstorm.set "groups", [g(a), g(b), g(c)]
    dotstorm.move(0, null, 2, null)
    expectMatch [g(b), g(a), g(c)]
    dotstorm.move(2, null, 0, null)
    expectMatch [g(c), g(b), g(a)]

  it "moves group adjacent group, right side", ->
    dotstorm.set "groups", [g(a), g(b), g(c)]
    dotstorm.move(0, null, 2, null, 1)
    expectMatch [g(b), g(c), g(a)]
    dotstorm.move(2, null, 0, null, 1)
    expectMatch [g(b), g(a), g(c)]

  it "moves idea into group, left side", ->
    dotstorm.set "groups", [g(a), g(b), g(c)]
    dotstorm.move(0, 0, 1, 0)
    expectMatch [g(a, b), g(c)]
    dotstorm.move(1, 0, 0, 1)
    expectMatch [g(a, c, b)]

    dotstorm.set "groups", [g(a, b), g(c, d)]
    dotstorm.move(1, 1, 0, 0)
    expectMatch [g(d, a, b), g(c)]
    
  it "moves idea into group, right side", ->
    dotstorm.set "groups", [g(a), g(b), g(c)]
    dotstorm.move(0, 0, 1, 0, 1)
    expectMatch [g(b, a), g(c)]
    dotstorm.move(1, 0, 0, 1, 1)
    expectMatch [g(b, a, c)]

  it "moves group into group, left side", ->
    dotstorm.set "groups", [g(a, b), g(c, d)]
    dotstorm.move(0, null, 1, 0)
    expectMatch [g(a, b, c, d)]

    dotstorm.set "groups", [g(a, b), g(c, d)]
    dotstorm.move(0, null, 1, 1)
    expectMatch [g(c, a, b, d)]

    dotstorm.set "groups", [g(a, b), g(c, d)]
    dotstorm.move(1, null, 0, 0)
    expectMatch [g(c, d, a, b)]

  it "moves group into group, right side", ->
    dotstorm.set "groups", [g(a, b), g(c, d)]
    dotstorm.move(0, null, 1, 0, 1)
    expectMatch [g(c, a, b, d)]

    dotstorm.set "groups", [g(a, b), g(c, d)]
    dotstorm.move(0, null, 1, 1, 1)
    expectMatch [g(c, d, a, b)]

    dotstorm.set "groups", [g(a, b), g(c, d)]
    dotstorm.move(1, null, 0, 0, 1)
    expectMatch [g(a, c, d, b)]

  it "moves things in and out of the trash", ->
    dotstorm.set "groups", [g(a, b), g(c, d)]
    dotstorm.move(0, 0, null, null)

    expectMatch [g(b), g(c, d)]
    expect(dotstorm.get("trash")).to.eql([a])

    dotstorm.move(1, null, null, null)
    expectMatch [g(b)]
    expect(dotstorm.get("trash")).to.eql([c, d, a])

    dotstorm.move(null, 0, 0, null)
    expect(dotstorm.get("trash")).to.eql([d, a])
    expectMatch [g(c), g(b)]

    dotstorm.move(null, 0, 0, 0)
    expect(dotstorm.get("trash")).to.eql([a])
    expectMatch [g(d, c), g(b)]

    dotstorm.move(0, null, null, 1)
    expect(dotstorm.get("trash")).to.eql([a, d, c])
    expectMatch [g(b)]

    dotstorm.move(null, 1, 1, null)
    expectMatch [g(b), g(d)]
    expect(dotstorm.get("trash")).to.eql([a, c])

