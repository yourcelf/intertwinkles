intertwinkles.connect_socket ->
  intertwinkles.build_footer($("footer"))


resizeH1 = ->
  width = $("h1").width()
  $("h1").css("font-size", Math.min(600, Math.max(30, width * 0.8)) + "%")
$(window).on "resize", resizeH1
resizeH1()
$("body").scrollspy({ target: "#sidenav" })

$("#signin").on "click", (event) ->
  event.preventDefault()
  opts = {
    siteName: "InterTwinkles"
    termsOfService: "/about/terms/"
    privacyPolicy: "/about/privacy/"
  }
  if window.location.protocol == "https:"
    opts.siteLogo = "/static/img/star-icon.png"
  navigator.id.request(opts)

navigator.id.watch {
  onlogin: (assertion) ->
    intertwinkles.onlogin(assertion)
  onlogout: ->
    intertwinkles.onlogout()
}
intertwinkles.user.on "login", ->
  window.location.href = window.location.href
