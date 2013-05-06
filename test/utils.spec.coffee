expect        = require 'expect.js'
_             = require 'underscore'
utils         = require '../lib/utils'

describe "utils", ->

  it "encodes CSV", ->
    expect(utils.array_to_csv([
      ["this", "that", 'quoted "things"', '"Yo", ze said'],
      ["wut", "ok", "yah", 0, undefined, null, "a\nb"]
    ])).to.be('''this,that,quoted ""things"","""Yo"", ze said"\nwut,ok,yah,0,,,"a\nb"''')

  it "absolutizes urls", ->
    expect(
      utils.absolutize_url("http://example.com", "/this/that")
    ).to.be("http://example.com/this/that")
    expect(
      utils.absolutize_url("http://example.com", "http://example2.com/this/that")
    ).to.be("http://example2.com/this/that")
    expect(
      utils.absolutize_url("https://example.com", "/this/that")
    ).to.be("https://example.com/this/that")

  it "Checks sharing with undefined or not groups", ->
    expect(utils.sharing_is_equal({
      group_id: undefined
    }, {
      group_id: "not undefined"
    })).to.be(false)

  it "Checks equality of sharing settings: empty lists", ->
    future = new Date()
    expect(utils.sharing_is_equal({
      public_view_until: future
      public_edit_until: future
      extra_viewers: []
      extra_editors: []
      group_id: 'any'
    }, {
      public_view_until: future
      public_edit_until: future
      extra_viewers: undefined
      extra_editors: undefined
      group_id: 'any'
    })).to.be(true)

    expect(utils.sharing_is_equal({
      public_view_until: future
      public_edit_until: future
      extra_viewers: ["some"]
      extra_editors: []
      group_id: 'any'
    }, {
      public_view_until: future
      public_edit_until: future
      extra_viewers: undefined
      extra_editors: undefined
      group_id: 'any'
    })).to.be(false)

  it "Checks equality of sharing settings: date strings", ->
    str = "2013-01-01T00:00:00Z"
    future = new Date(str)
    expect(utils.sharing_is_equal({
      public_view_until: future
      public_edit_until: future
      extra_viewers: []
      extra_editors: []
      group_id: 'any'
    }, {
      public_view_until: str
      public_edit_until: str
      extra_viewers: undefined
      extra_editors: undefined
      group_id: 'any'
    })).to.be(true)

    str2 = "2013-01-01T00:00:01Z"
    expect(utils.sharing_is_equal({
      public_view_until: future
      public_edit_until: future
      extra_viewers: []
      extra_editors: []
      group_id: 'any'
    }, {
      public_view_until: str2
      public_edit_until: str
      extra_viewers: undefined
      extra_editors: undefined
      group_id: 'any'
    })).to.be(false)

  it "Checks equality of sharing settings: far future dates", ->
    far_future1 = new Date("3013-01-01T00:00:00Z")
    far_future2 = new Date("3014-01-01T00:00:00Z")
    expect(utils.sharing_is_equal({
      public_view_until: undefined
      public_edit_until: far_future1
      extra_viewers: []
      extra_editors: []
      group_id: 'any'
    }, {
      public_view_until: undefined
      public_edit_until: far_future2
      extra_viewers: undefined
      extra_editors: undefined
      group_id: 'any'
    })).to.be(true)

    expect(utils.sharing_is_equal({
      public_view_until: undefined
      public_edit_until: far_future1
      extra_viewers: []
      extra_editors: []
      group_id: 'any'
    }, {
      public_view_until: undefined
      public_edit_until: new Date()
      extra_viewers: undefined
      extra_editors: undefined
      group_id: 'any'
    })).to.be(false)

  it "Checks equality of sharing settings: group", ->
    str = "2013-01-01T00:00:00Z"
    future = new Date(str)
    expect(utils.sharing_is_equal({
      public_view_until: future
      public_edit_until: future
      extra_viewers: ["one"]
      extra_editors: ["one"]
      group_id: 'group1'
    }, {
      public_view_until: str
      public_edit_until: str
      extra_viewers: ["one"]
      extra_editors: ["one"]
      group_id: 'group1'
    })).to.be(true)
    expect(utils.sharing_is_equal({
      public_view_until: future
      public_edit_until: future
      extra_viewers: ["one"]
      extra_editors: ["one"]
      group_id: 'group1'
    }, {
      public_view_until: str
      public_edit_until: str
      extra_viewers: ["one"]
      extra_editors: ["one"]
      group_id: 'group2'
    })).to.be(false)

  it "Checks equality of sharing settings: advertise", ->
    str = "2013-01-01T00:00:00Z"
    future = new Date(str)
    expect(utils.sharing_is_equal({
      advertise: false
      public_view_until: future
      public_edit_until: future
      extra_viewers: ["one"]
      extra_editors: ["one"]
      group_id: 'group1'
    }, {
      advertise: undefined
      public_view_until: str
      public_edit_until: str
      extra_viewers: ["one"]
      extra_editors: ["one"]
      group_id: 'group1'
    })).to.be(true)
    expect(utils.sharing_is_equal({
      advertise: undefined
      public_view_until: future
      public_edit_until: future
      extra_viewers: ["one"]
      extra_editors: ["one"]
      group_id: 'group1'
    }, {
      advertise: true
      public_view_until: str
      public_edit_until: str
      extra_viewers: ["one"]
      extra_editors: ["one"]
      group_id: 'group1'
    })).to.be(false)
    expect(utils.sharing_is_equal({
      advertise: false
      public_view_until: future
      public_edit_until: future
      extra_viewers: ["one"]
      extra_editors: ["one"]
      group_id: 'group1'
    }, {
      advertise: true
      public_view_until: str
      public_edit_until: str
      extra_viewers: ["one"]
      extra_editors: ["one"]
      group_id: 'group1'
    })).to.be(false)
    expect(utils.sharing_is_equal({
      advertise: true
      public_view_until: future
      public_edit_until: future
      extra_viewers: ["one"]
      extra_editors: ["one"]
      group_id: 'group1'
    }, {
      advertise: true
      public_view_until: str
      public_edit_until: str
      extra_viewers: ["one"]
      extra_editors: ["one"]
      group_id: 'group1'
    })).to.be(true)
