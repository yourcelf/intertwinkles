#= require ../urlize

#
# Utilities
#

if INITIAL_DATA.time
  intertwinkles.BROWSER_CLOCK_SKEW = INITIAL_DATA.time - new Date().getTime()
else
  intertwinkles.BROWSER_CLOCK_SKEW = 0

class intertwinkles.AutoUpdatingDate extends Backbone.View
  tagName: "span"
  initialize: (options) ->
    @date = intertwinkles.parse_date(options.date)
    @$el.addClass("date")

  remove: =>
    clearTimeout(@timeout) if @timeout?
    super()

  render: =>
    clearTimeout(@timeout) if @timeout?
    #N.B. Duplicates logic below in simple_date
    now = intertwinkles.now()
    date = @date
    if now.getFullYear() != date.getFullYear()
      str = date.toString("MMM d, yyyy")
    else if now.getMonth() != date.getMonth() or now.getDate() != date.getDate()
      str = date.toString("MMM d")
    else
      diff = now.getTime() - date.getTime()
      seconds = diff / 1000
      if seconds > (60 * 60)
        str = parseInt(seconds / 60 / 60) + "h"
        @timeout = setTimeout @render, 60000 * 15
      else if seconds > 60
        str = parseInt(seconds / 60) + "m"
        @timeout = setTimeout @render, 60000
      else
        if parseInt(seconds) < 0
          str = "now"
        else
          str = parseInt(seconds) + "s"
        @timeout = setTimeout @render, 15000
    @$el.attr("title", date.toString("dddd, MMMM dd, yyyy h:mm:ss tt"))
    @$el.html(str)
    this

intertwinkles.simple_date = (date, bare=false) ->
  #N.B. duplicates logic above in AutoUpdatingDate
  date = intertwinkles.parse_date(date)
  now = intertwinkles.now()
  if now.getFullYear() != date.getFullYear()
    str = date.toString("MMM d, YYYY")
  else if now.getMonth() != date.getMonth() or now.getDate() != date.getDate()
    str = date.toString("MMM d")
  else
    diff = now.getTime() - date.getTime()
    seconds = diff / 1000
    if seconds > (60 * 60)
      str = parseInt(seconds / 60 / 60) + "h"
    else if seconds > 60
      str = parseInt(seconds / 60) + "m"
    else if seconds < 0
      str = "now"
    else
      str = parseInt(seconds) + "s"

  if bare
    return str
  return """<span class='date' title='#{date.toString("dddd, MMMM dd, yyyy h:mm:ss tt")}'>
      #{str}
    </span>"""

intertwinkles.absolute_date = (date, bare=false) ->
  date = intertwinkles.parse_date(date)
  now = intertwinkles.now()
  if now.getFullYear() != date.getFullYear()
    str = date.toString("MMM d, YYYY")
  else
    str = date.toString("MMM d")
  if bare
    return str
  return """<span class='date' title='#{date.toString("dddd, MMMM dd, yyyy h:mm:ss tt")}'>
    #{str}
  </span>"""

intertwinkles.user_icon = (user_id, name, size="small") ->
  user = intertwinkles.users?[user_id]
  if user?
    return "<img src='#{_.escape(user.icon[size])}' title='#{user.name}' />"
  else
    return "<span style='width: 32px;'><i class='icon icon-user' title='#{name}'></i></span>"

intertwinkles.inline_user = (user_id, name, size="small") ->
  name ?= "Anonymous"
  user = intertwinkles.users?[user_id]
  if user? and user.icon?
    return "<img src='#{_.escape(user.icon[size])}' /> #{_.escape(user.name)}"
  else
    return "<span style='width: 32px;'><i class='icon icon-user'></i></span> #{user?.name or name}"

intertwinkles.markup = (text) ->
  if text
    text = urlize(text, 50, true, _.escape)
    text = text.replace(/\n/g, '\n<br />')
    return text
  return ""

intertwinkles.slugify = (name) ->
  return name.toLowerCase().replace(/[^a-z0-9_\.]/g, '-')

html_colors = [
  [0x80, 0x00, 0x00, "maroon"],
  [0x8B, 0x00, 0x00, "darkred"],
  [0xFF, 0x00, 0x00, "red"],
  [0xFF, 0xB6, 0xC1, "lightpink"],
  [0xDC, 0x14, 0x3C, "crimson"],
  [0xDB, 0x70, 0x93, "palevioletred"],
  [0xFF, 0x69, 0xB4, "hotpink"],
  [0xFF, 0x14, 0x93, "deeppink"],
  [0xC7, 0x15, 0x85, "mediumvioletred"],
  [0x80, 0x00, 0x80, "purple"],
  [0x8B, 0x00, 0x8B, "darkmagenta"],
  [0xDA, 0x70, 0xD6, "orchid"],
  [0xD8, 0xBF, 0xD8, "thistle"],
  [0xDD, 0xA0, 0xDD, "plum"],
  [0xEE, 0x82, 0xEE, "violet"],
  [0xFF, 0x00, 0xFF, "fuchsia"],
  [0xFF, 0x00, 0xFF, "magenta"],
  [0xBA, 0x55, 0xD3, "mediumorchid"],
  [0x94, 0x00, 0xD3, "darkviolet"],
  [0x99, 0x32, 0xCC, "darkorchid"],
  [0x8A, 0x2B, 0xE2, "blueviolet"],
  [0x4B, 0x00, 0x82, "indigo"],
  [0x93, 0x70, 0xDB, "mediumpurple"],
  [0x6A, 0x5A, 0xCD, "slateblue"],
  [0x7B, 0x68, 0xEE, "mediumslateblue"],
  [0x00, 0x00, 0x8B, "darkblue"],
  [0x00, 0x00, 0xCD, "mediumblue"],
  [0x00, 0x00, 0xFF, "blue"],
  [0x00, 0x00, 0x80, "navy"],
  [0x19, 0x19, 0x70, "midnightblue"],
  [0x48, 0x3D, 0x8B, "darkslateblue"],
  [0x41, 0x69, 0xE1, "royalblue"],
  [0x64, 0x95, 0xED, "cornflowerblue"],
  [0xB0, 0xC4, 0xDE, "lightsteelblue"],
  [0xF0, 0xF8, 0xFF, "aliceblue"],
  [0xF8, 0xF8, 0xFF, "ghostwhite"],
  [0xE6, 0xE6, 0xFA, "lavender"],
  [0x1E, 0x90, 0xFF, "dodgerblue"],
  [0x46, 0x82, 0xB4, "steelblue"],
  [0x00, 0xBF, 0xFF, "deepskyblue"],
  [0x70, 0x80, 0x90, "slategray"],
  [0x77, 0x88, 0x99, "lightslategray"],
  [0x87, 0xCE, 0xFA, "lightskyblue"],
  [0x87, 0xCE, 0xEB, "skyblue"],
  [0xAD, 0xD8, 0xE6, "lightblue"],
  [0x00, 0x80, 0x80, "teal"],
  [0x00, 0x8B, 0x8B, "darkcyan"],
  [0x00, 0xCE, 0xD1, "darkturquoise"],
  [0x00, 0xFF, 0xFF, "cyan"],
  [0x48, 0xD1, 0xCC, "mediumturquoise"],
  [0x5F, 0x9E, 0xA0, "cadetblue"],
  [0xAF, 0xEE, 0xEE, "paleturquoise"],
  [0xE0, 0xFF, 0xFF, "lightcyan"],
  [0xF0, 0xFF, 0xFF, "azure"],
  [0x20, 0xB2, 0xAA, "lightseagreen"],
  [0x40, 0xE0, 0xD0, "turquoise"],
  [0xB0, 0xE0, 0xE6, "powderblue"],
  [0x2F, 0x4F, 0x4F, "darkslategray"],
  [0x7F, 0xFF, 0xD4, "aquamarine"],
  [0x00, 0xFA, 0x9A, "mediumspringgreen"],
  [0x66, 0xCD, 0xAA, "mediumaquamarine"],
  [0x00, 0xFF, 0x7F, "springgreen"],
  [0x3C, 0xB3, 0x71, "mediumseagreen"],
  [0x2E, 0x8B, 0x57, "seagreen"],
  [0x32, 0xCD, 0x32, "limegreen"],
  [0x00, 0x64, 0x00, "darkgreen"],
  [0x00, 0x80, 0x00, "green"],
  [0x00, 0xFF, 0x00, "lime"],
  [0x22, 0x8B, 0x22, "forestgreen"],
  [0x8F, 0xBC, 0x8F, "darkseagreen"],
  [0x90, 0xEE, 0x90, "lightgreen"],
  [0x98, 0xFB, 0x98, "palegreen"],
  [0xF5, 0xFF, 0xFA, "mintcream"],
  [0xF0, 0xFF, 0xF0, "honeydew"],
  [0x7F, 0xFF, 0x00, "chartreuse"],
  [0x7C, 0xFC, 0x00, "lawngreen"],
  [0x6B, 0x8E, 0x23, "olivedrab"],
  [0x55, 0x6B, 0x2F, "darkolivegreen"],
  [0x9A, 0xCD, 0x32, "yellowgreen"],
  [0xAD, 0xFF, 0x2F, "greenyellow"],
  [0xF5, 0xF5, 0xDC, "beige"],
  [0xFA, 0xF0, 0xE6, "linen"],
  [0xFA, 0xFA, 0xD2, "lightgoldenrodyellow"],
  [0x80, 0x80, 0x00, "olive"],
  [0xFF, 0xFF, 0x00, "yellow"],
  [0xFF, 0xFF, 0xE0, "lightyellow"],
  [0xFF, 0xFF, 0xF0, "ivory"],
  [0xBD, 0xB7, 0x6B, "darkkhaki"],
  [0xF0, 0xE6, 0x8C, "khaki"],
  [0xEE, 0xE8, 0xAA, "palegoldenrod"],
  [0xF5, 0xDE, 0xB3, "wheat"],
  [0xFF, 0xD7, 0x00, "gold"],
  [0xFF, 0xFA, 0xCD, "lemonchiffon"],
  [0xFF, 0xEF, 0xD5, "papayawhip"],
  [0xB8, 0x86, 0x0B, "darkgoldenrod"],
  [0xDA, 0xA5, 0x20, "goldenrod"],
  [0xFA, 0xEB, 0xD7, "antiquewhite"],
  [0xFF, 0xF8, 0xDC, "cornsilk"],
  [0xFD, 0xF5, 0xE6, "oldlace"],
  [0xFF, 0xE4, 0xB5, "moccasin"],
  [0xFF, 0xDE, 0xAD, "navajowhite"],
  [0xFF, 0xA5, 0x00, "orange"],
  [0xFF, 0xE4, 0xC4, "bisque"],
  [0xD2, 0xB4, 0x8C, "tan"],
  [0xFF, 0x8C, 0x00, "darkorange"],
  [0xDE, 0xB8, 0x87, "burlywood"],
  [0x8B, 0x45, 0x13, "saddlebrown"],
  [0xF4, 0xA4, 0x60, "sandybrown"],
  [0xFF, 0xEB, 0xCD, "blanchedalmond"],
  [0xFF, 0xF0, 0xF5, "lavenderblush"],
  [0xFF, 0xF5, 0xEE, "seashell"],
  [0xFF, 0xFA, 0xF0, "floralwhite"],
  [0xFF, 0xFA, 0xFA, "snow"],
  [0xCD, 0x85, 0x3F, "peru"],
  [0xFF, 0xDA, 0xB9, "peachpuff"],
  [0xD2, 0x69, 0x1E, "chocolate"],
  [0xA0, 0x52, 0x2D, "sienna"],
  [0xFF, 0xA0, 0x7A, "lightsalmon"],
  [0xFF, 0x7F, 0x50, "coral"],
  [0xE9, 0x96, 0x7A, "darksalmon"],
  [0xFF, 0xE4, 0xE1, "mistyrose"],
  [0xFF, 0x45, 0x00, "orangered"],
  [0xFA, 0x80, 0x72, "salmon"],
  [0xFF, 0x63, 0x47, "tomato"],
  [0xBC, 0x8F, 0x8F, "rosybrown"],
  [0xFF, 0xC0, 0xCB, "pink"],
  [0xCD, 0x5C, 0x5C, "indianred"],
  [0xF0, 0x80, 0x80, "lightcoral"],
  [0xA5, 0x2A, 0x2A, "brown"],
  [0xB2, 0x22, 0x22, "firebrick"],
  [0x00, 0x00, 0x00, "black"],
  [0x69, 0x69, 0x69, "dimgray"],
  [0x80, 0x80, 0x80, "gray"],
  [0xA9, 0xA9, 0xA9, "darkgray"],
  [0xC0, 0xC0, 0xC0, "silver"],
  [0xD3, 0xD3, 0xD3, "lightgrey"],
  [0xDC, 0xDC, 0xDC, "gainsboro"],
  [0xF5, 0xF5, 0xF5, "whitesmoke"],
  [0xFF, 0xFF, 0xFF, "white"],
]
intertwinkles.match_color = (hexstr) ->
  r1 = parseInt(hexstr[0...2], 16)
  g1 = parseInt(hexstr[2...4], 16)
  b1 = parseInt(hexstr[4...6], 16)
  distance = 255 * 3
  best = html_colors[0][3]
  for [r2, g2, b2, name] in html_colors
    # Lame, lame, RGB based additive distance.  Not great.
    diff = Math.abs(r1 - r2) + Math.abs(g1 - g2) + Math.abs(b1 - b2)
    if diff < distance
      distance = diff
      best = name
  return best

intertwinkles.instasearch = (form_selector, results_selector, callback) ->
  # Given a page with a search form which returns results on the same page,
  # eliminate the page load, and make every keypress on that form trigger
  # instant search.  Do this using pushState in the browser, and parsing the
  # DOM of the full page returned (e.g. the server thinks you're just reloading
  # the whole page). 
  if (window.history.pushState)
    subTimeout = null
    submit_it = ->
      $(form_selector).submit()
    $("select", form_selector).on('change', submit_it)
    $("input[type=text]", form_selector).on('keyup', submit_it)
    $(form_selector).submit (event) ->
      event.preventDefault()
      $(".loading", results_selector).show()
      clearTimeout(subTimeout) if (subTimeout)
      subTimeout = setTimeout ->
        $.ajax {
          url:"?" + $(form_selector).formSerialize(),
          type: 'GET',
          success: (data) ->
            new_doc = $("<div>" + data + "</div>")
            $(results_selector, document).html(
              $(results_selector, new_doc).html()
            )
            history.replaceState({}, "", "?" + $(form_selector).formSerialize())
            callback?()
          error: (data) ->
            console.info("error", data)
            alert("Server error!")
            callback?("error")
        }
        $(this).ajaxSubmit()
      , 500

intertwinkles.sub_vars = (scope=document) ->
  $(".varsub", scope).each ->
    $el = $(this)

    #
    # Dashboard fill-ins
    #
    if $el.attr("data-date")
      date = new intertwinkles.AutoUpdatingDate(date: $el.attr("data-date"))
      $el.html(date.el)
      date.render()

    else if $el.attr("data-group-id")
      group = intertwinkles.groups?[$el.attr("data-group-id")]
      if not group?
        $el.hide()
      else
        $el.show().html(group.name)

    else if $el.attr("data-user-id")
      user = intertwinkles.users?[$el.attr("data-user-id")]
      if user?
        $el.html "<img src='#{user.icon.tiny}' /> #{user.name}"
      else
        $el.html "<i class='icon-user'></i> (protected)"

  $(".markmeup", scope).each ->
    $(this).html(intertwinkles.markup($(this).html()))

  $(".tile-link").on "click", (event) ->
    href = $("a", event.currentTarget).attr("href")
    if href
      window.location.href = href

