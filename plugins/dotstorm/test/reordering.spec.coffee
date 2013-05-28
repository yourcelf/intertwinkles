expect       = require 'expect.js'
uuid         = require 'node-uuid'
require "better-stack-traces"

rearranger   = require '../assets/dotstorm/js/rearrange_groups'

describe "Dotstorm idea reordering", ->
  # idea IDs
  a = 'a'
  b = 'b'
  c = 'c'
  d = 'd'
  groups = []
  trash  = []
  # Create a group
  g = (ids...) -> return {_id: uuid.v4(), ideas: ids}


  # Ensure groups are equal, excluding group ID's, which are random.
  expectMatch = (list) ->
    expect(groups.length).to.be(list.length)
    for i in [0...list.length]
      expect(groups[i].ideas).to.eql(list[i].ideas)

  it "generates a UUID", ->
    expect(rearranger.uuid().length).to.be 36

  it "expects the right matches", ->
    groups = [g(a)]
    expectMatch [g(a)]
    expect(-> expectMatch [g(b)]).to.throwError()
    expect(-> expectMatch [g(a,b)]).to.throwError()


  it "validates moves", ->
    verify = rearranger.verify_rearrange_args
    groups = [g(a,b), g(c)]
    trash = [d]
    # Just do invalid moves here.  Valid ones are covered by other tests.
    
    # invalid offset
    expect(verify(groups, trash, [0, 0, 1, 0, -1])).to.be(false)
    expect(verify(groups, trash, [0, 0, 1, 0, 2])).to.be(false)
    # Source group/idea both null
    expect(verify(groups, trash, [null, null, 1, 0, 2])).to.be(false)
    # Source group null, source idea out of bounds
    expect(verify(groups, trash, [null, 1, 1, 0, 2])).to.be(false)
    # Source group out of bounds
    expect(verify(groups, trash, [2, 0, 1, 0, 2])).to.be(false)
    expect(verify(groups, trash, [-1, 0, 1, 0, 0])).to.be(false)
    # Source group ok, source idea out of bounds
    expect(verify(groups, trash, [0, 2, 1, 0, 2])).to.be(false)
    expect(verify(groups, trash, [0, -1, 1, 0, 0])).to.be(false)
    # Dest null, dest idea out of bounds
    expect(verify(groups, trash, [0, 0, null, 2, 0])).to.be(false)
    expect(verify(groups, trash, [0, 0, null, -1, 0])).to.be(false)
    # Dest group out of bounds.
    expect(verify(groups, trash, [0, 0, 3, 0, 0])).to.be(false)
    expect(verify(groups, trash, [0, 0, -1, 0, 0])).to.be(false)
    # Dest idea out of bounds
    expect(verify(groups, trash, [0, 0, 1, 2, 0])).to.be(false)
    expect(verify(groups, trash, [0, 0, 1, -1, 0])).to.be(false)
    # Take out the trash. :)
    trash = []

  it "moves idea adjacent group, left side", ->
    groups = [g(a), g(b), g(c)]
    rearranger.rearrange(groups, trash, [0, 0, 2, null, 0]) # move a adjacent c
    expectMatch [g(b), g(a), g(c)]
    rearranger.rearrange(groups, trash, [2, 0, 0, null, 0]) # move c adjacent b
    expectMatch [g(c), g(b), g(a)]

  it "moves idea adjacent group, right side", ->
    groups = [g(a), g(b), g(c)]
    rearranger.rearrange(groups, trash, [0, 0, 2, null, 1])
    expectMatch [g(b), g(c), g(a)]
    rearranger.rearrange(groups, trash, [2, 0, 0, null, 1])
    expectMatch [g(b), g(a), g(c)]

  it "moves idea out of group, left side", ->
    groups = [g(a, b), g(c, d)]
    rearranger.rearrange(groups, trash, [0, 0, 1, null, 0])
    expectMatch [g(b), g(a), g(c, d)]

  it "moves idea out of group, right side", ->
    groups = [g(a, b), g(c, d)]
    rearranger.rearrange(groups, trash, [0, 0, 1, null, 1])
    expectMatch [g(b), g(c, d), g(a)]

  it "moves idea within group, left side", ->
    groups = [g(a, b, c), g(d)]
    rearranger.rearrange(groups, trash, [0, 0, 0, 1, 0])
    expectMatch [g(a, b, c), g(d)]
    rearranger.rearrange(groups, trash, [0, 0, 0, 2, 0])
    expectMatch [g(b, a, c), g(d)]

  it "moves idea within group, right side", ->
    groups = [g(a, b, c), g(d)]
    rearranger.rearrange(groups, trash, [0, 0, 0, 1, 1])
    expectMatch [g(b, a, c), g(d)]
    rearranger.rearrange(groups, trash, [0, 0, 0, 2, 1])
    expectMatch [g(a, c, b), g(d)]

  it "moves group adjacent group, left side", ->
    groups = [g(a), g(b), g(c)]
    rearranger.rearrange(groups, trash, [0, null, 2, null, 0])
    expectMatch [g(b), g(a), g(c)]
    rearranger.rearrange(groups, trash, [2, null, 0, null, 0])
    expectMatch [g(c), g(b), g(a)]

  it "moves group adjacent group, right side", ->
    groups = [g(a), g(b), g(c)]
    rearranger.rearrange(groups, trash, [0, null, 2, null, 1])
    expectMatch [g(b), g(c), g(a)]
    rearranger.rearrange(groups, trash, [2, null, 0, null, 1])
    expectMatch [g(b), g(a), g(c)]

  it "moves idea into group, left side", ->
    groups = [g(a), g(b), g(c)]
    rearranger.rearrange(groups, trash, [0, 0, 1, 0, 0])
    expectMatch [g(a, b), g(c)]
    rearranger.rearrange(groups, trash, [1, 0, 0, 1, 0])
    expectMatch [g(a, c, b)]

    groups = [g(a, b), g(c, d)]
    rearranger.rearrange(groups, trash, [1, 1, 0, 0, 0])
    expectMatch [g(d, a, b), g(c)]
    
  it "moves idea into group, right side", ->
    groups = [g(a), g(b), g(c)]
    rearranger.rearrange(groups, trash, [0, 0, 1, 0, 1])
    expectMatch [g(b, a), g(c)]
    rearranger.rearrange(groups, trash, [1, 0, 0, 1, 1])
    expectMatch [g(b, a, c)]

  it "moves group into group, left side", ->
    groups = [g(a, b), g(c, d)]
    rearranger.rearrange(groups, trash, [0, null, 1, 0, 0])
    expectMatch [g(a, b, c, d)]

    groups = [g(a, b), g(c, d)]
    rearranger.rearrange(groups, trash, [0, null, 1, 1, 0])
    expectMatch [g(c, a, b, d)]

    groups = [g(a, b), g(c, d)]
    rearranger.rearrange(groups, trash, [1, null, 0, 0, 0])
    expectMatch [g(c, d, a, b)]

  it "moves group into group, right side", ->
    groups = [g(a, b), g(c, d)]
    rearranger.rearrange(groups, trash, [0, null, 1, 0, 1])
    expectMatch [g(c, a, b, d)]

    groups = [g(a, b), g(c, d)]
    rearranger.rearrange(groups, trash, [0, null, 1, 1, 1])
    expectMatch [g(c, d, a, b)]

    groups = [g(a, b), g(c, d)]
    rearranger.rearrange(groups, trash, [1, null, 0, 0, 1])
    expectMatch [g(a, c, d, b)]

  it "moves things in and out of the trash", ->
    groups = [g(a, b), g(c, d)]
    rearranger.rearrange(groups, trash, [0, 0, null, null, 0])

    expectMatch [g(b), g(c, d)]
    expect(trash).to.eql([a])

    rearranger.rearrange(groups, trash, [1, null, null, null, 0])
    expectMatch [g(b)]
    expect(trash).to.eql([c, d, a])

    rearranger.rearrange(groups, trash, [null, 0, 0, null, 0])
    expect(trash).to.eql([d, a])
    expectMatch [g(c), g(b)]

    rearranger.rearrange(groups, trash, [null, 0, 0, 0, 0])
    expect(trash).to.eql([a])
    expectMatch [g(d, c), g(b)]

    rearranger.rearrange(groups, trash, [0, null, null, 1, 0])
    expect(trash).to.eql([a, d, c])
    expectMatch [g(b)]

    rearranger.rearrange(groups, trash, [null, 1, 1, null, 0])
    expectMatch [g(b), g(d)]
    expect(trash).to.eql([a, c])

