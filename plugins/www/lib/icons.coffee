im        = require 'imagemagick'
name_list = require '../../../assets/js/intertwinkles_icon_chooser.json'
path      = require 'path'
fs        = require 'fs'
_         = require 'underscore'

# Get the range of icons, and map of icon names.
MIN_ICON = 1000
MAX_ICON = 0
name_map = {}
for entry in name_list
  name_map[entry.pk] = entry.name
  MIN_ICON = Math.min(entry.pk, MIN_ICON)
  MAX_ICON = Math.max(entry.pk, MAX_ICON)

#
# Render icons for 16, 32, and 64 px. Return an icon definition appropriate for
# the User schema.
#
render_icon = (pk, color, cb) ->
  sizes =  ["16", "32", "64"]
  errors = []
  paths = {}
  done = 0
  finish = (err) ->
    errors.push(err) if err?
    done += 1
    if done == sizes.length
      if errors.length == 0
          cb(null, {pk: pk, name: name_map[pk], color: color, sizes: paths})
        else
          cb(errors)

  for size in sizes
    dest_icon = __dirname + "/../assets/user_icons/#{color}-#{name_map[pk]}-#{size}.png"
    paths[size] = path.relative(__dirname + "/../assets/", dest_icon)

    do (size, dest_icon) ->
      fs.exists dest_icon, (exists) ->
        if exists
          finish(null)
        else
          source_icon = __dirname + "/../assets/source_icons/#{pk}-#{size}.png"
          convert_args = [
            source_icon,
            "+level-colors",
            "##{color},",
            "-gravity",
            "center",
            "-background",
            "transparent",
            "-extent",
            "#{size}x#{size}",
            dest_icon
          ]
          im.convert(convert_args, finish)
#
# Generate a random icon and color. Useful for first-run user profiles.
#
get_random_icon = (cb) ->
  pk = Math.round(Math.random() * (MAX_ICON - MIN_ICON) + MIN_ICON)
  colors = []
  for i in [0...3]
    val = Math.round(Math.random() * 255).toString(16)
    if val.length == 1
      val = "0#{val}"
    colors.push(val)
  render_icon(pk, colors.join(""), cb)

get_icon_name = (pk) ->
  #XXX could make this faster with a binary search
  return _.find name_list, (n) -> n.pk == pk

module.exports = { render_icon, get_random_icon, get_icon_name }
