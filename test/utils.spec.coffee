expect        = require 'expect.js'
_             = require 'underscore'
utils         = require '../lib/utils'

describe "utils", ->

  it "encodes CSV", ->
    expect(utils.array_to_csv([
      ["this", "that", 'quoted "things"', '"Yo", ze said'],
      ["wut", "ok", "yah", 0, undefined, null, "a\nb"]
    ])).to.be('''this,that,quoted ""things"","""Yo"", ze said"\nwut,ok,yah,0,,,"a\nb"''')
