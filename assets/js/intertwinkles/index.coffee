#= require ../vendor/sockjs-0.3.4.js
#= require ../vendor/jquery.js
#= require ../vendor/jquery-ui-1.9.1.custom.js
#= require ../vendor/jquerypp.custom.js
#= require ../vendor/jquery.form.js
#= require ../vendor/jquery.cookie.js
#= require ../vendor/jquery.qrcode.min.js
#= require ../vendor/underscore.js
#= require ../vendor/underscore-autoescape.js
#= require ../vendor/backbone.js
#= require ../vendor/date.js
#= require ../vendor/jscolor/jscolor.js
#= require ../../bootstrap/js/bootstrap-transition.js
#= require ../../bootstrap/js/bootstrap-dropdown.js
#= require ../../bootstrap/js/bootstrap-transition.js
#= require ../../bootstrap/js/bootstrap-modal.js
#= require ../../bootstrap/js/bootstrap-dropdown.js
#= require ../../bootstrap/js/bootstrap-scrollspy.js
#= require ../../bootstrap/js/bootstrap-tab.js
#= require ../../bootstrap/js/bootstrap-tooltip.js
#= require ../../bootstrap/js/bootstrap-popover.js
#= require ../../bootstrap/js/bootstrap-alert.js
#= require ../../bootstrap/js/bootstrap-button.js
#= require ../../bootstrap/js/bootstrap-collapse.js
#= require ../../bootstrap/js/bootstrap-carousel.js
#= require ../../bootstrap/js/bootstrap-typeahead.js
#= require ../../bootstrap/js/bootstrap-affix.js
#= require ../../bootstrap/bootstrap-modal-2/bootstrap-modalmanager.js
#= require ../../bootstrap/bootstrap-modal-2/bootstrap-modal.js
#= require ../flash
#= require ./common
#= require ./socket
#= require ./authentication
#= require ./profiles
#= require ./ui_components
#= require ./sharing
#= require ./events
#= require ./notifications
#= require ./twinkles
#= require ./utilities

$.fn.modal.defaults.maxHeight = -> $(window).height() - 165

intertwinkles.twunklify = (scope) ->
  $("span.intertwinkles", scope or document).on "mouseover", ->
    $el = $(this)
    unless $el.hasClass("twunkled")
      $el.addClass("twunkled")
      letters = $el.text()
      spans = []
      for i in [0...letters.length]
        spans.push("<span>#{letters.substr(i, 1)}</span>")
      $el.html(spans.join(""))
    $el.find("span").each (i, el)->
      setTimeout( ->
        el.className = "bump"
        setTimeout((-> el.className = ""), 100)
      , i * 50)

intertwinkles.modalvidify = (scope) ->
  $(".modal-video", scope or document).on "click", ->
    width = parseInt($(this).attr("data-width"))
    height = parseInt($(this).attr("data-height"))
    mod = $("<div class='modal' role='dialog'></div>").css {
      display: "none"
      width: "#{width + 10}px"
      height: "#{height + 10}px"
      "background-color": "black"
      "text-align": "center"
      padding: "5px 5px 5px 5px"
    }
    mod.append("<iframe width='#{width}' height='#{height}' src='#{$(this).attr("data-url")}?autoplay=1&cc_load_policy=1' frameborder='0' allowfullscreen></iframe>")
    $("body").append(mod)
    mod.on('hidden', -> mod.remove())
    mod.modal()
    return false

$(document).ready ->
  intertwinkles.twunklify()
  intertwinkles.modalvidify()

  $(".search-menu-trigger").on "click", ->
    el = $(".dropdown-menu.search input[name=q]")
    interval = setInterval ->
      if el.is(":visible")
        el.select()
        clearInterval(interval)
    , 100
    setTimeout ->
      if interval
        clearInterval(interval)
    , 1000
