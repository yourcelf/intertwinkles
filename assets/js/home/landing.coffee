intertwinkles.connect_socket ->
  intertwinkles.build_footer($("footer"))

resizeH1 = ->
  width = $("h1").width()
  $("h1").css("font-size", Math.min(600, Math.max(30, width * 0.8)) + "%")
$(window).on "resize", resizeH1
resizeH1()

$(".app-image").hover(
  (evt) -> $(this).closest(".app-tile").find(".app-title").addClass("hover")
  (evt) -> $(this).closest(".app-tile").find(".app-title").removeClass("hover")
)
$(".app-title").hover(
  (evt) -> $(this).closest(".app-tile").find(".app-image").addClass("hover")
  (evt) -> $(this).closest(".app-tile").find(".app-image").removeClass("hover")
)

$(".signin-link").on "click", (event) ->
  event.preventDefault()
  intertwinkles.request_login()

intertwinkles.user.on "login", ->
  # Reload the page.
  window.location.href = window.location.href
