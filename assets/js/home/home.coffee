intertwinkles.connect_socket ->
  intertwinkles.build_toolbar($("header"), {applabel: "home"})
  intertwinkles.build_footer($("footer"))

sub_vars = (scope=document) ->
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
      group = intertwinkles.groups[$el.attr("data-group-id")]
      if not group?
        $el.hide()
      else
        $el.show().html(group.name)

    else if $el.attr("data-user-id")
      user = intertwinkles.users[$el.attr("data-user-id")]
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

sub_vars()
window.sub_vars = sub_vars
