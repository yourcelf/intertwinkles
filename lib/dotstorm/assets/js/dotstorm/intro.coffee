
class ds.Intro extends Backbone.View
  #
  # A front-page form for opening or creating new dotstorms.
  #
  chars: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz1234567890"
  template: _.template $("#intro").html() or ""
  events:
    'submit #named': 'openNamed'
    'submit #random': 'openRandom'
  render: =>
    @$el.html @template()
    this

  openNamed: (event) =>
    name = @$("#id_join").val()
    if name != ''
      slug = ds.Dotstorm.prototype.slugify(name)
      @trigger "open", slug, name
    return false

  openRandom: (event) =>
    randomChar = =>
      @chars.substr parseInt(Math.random() * @chars.length), 1
    slug = (randomChar() for i in [0...12]).join("")
    @trigger "open", slug, ""

    return false
