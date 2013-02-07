# equivalent to python's string.endswith(substr)
endswith = (a, b) -> return a.substr(a.length - b.length, b.length) == b

# equivalent to python's string.startswith(substr)
startswith = (a, b) -> return a.substr(0, b.length) == b

# equivalent to python's string.count(substr)
count_occurrances = (str, substr) ->
  n = 0
  pos = 0
  while true
    pos = str.indexOf(substr, pos)
    if pos >= 0
      n += 1
      pos += substr.length
    else
      return n

# rsplit(str, separator, max) equivalent to python's str.rsplit(sep, max)
rsplit = (str, sep, max) ->
  split = str.split(sep || /\s+/)
  if max?
    return [ split.slice(0, -max).join(sep) ].concat(split.slice(-max))
  return split

# Adaptation of django.utils.html.urlize
simple_url_re = /^https?:\/\/\w/
simple_url_2_re = /^www\.|^(?!http)\w[^@]+\.(com|edu|gov|int|mil|net|org)$/
simple_email_re = /^\S+@\S+\.\S+$/
urlize = (text, trim_url_limit=null, nofollow=true, escape=(->)) ->
  trim_url = (x) ->
    if trim_url_limit? and x.length > trim_url_limit
      return "#{x.substr(0, trim_url_limit - 3)}..."
    return x

  words = text.split(/(\s+)/)
  for word, i in words
    if /[\.@:]/.test(word)
      [lead, middle, trail] = ['', word, '']
      for punctuation in ['.', ',', ':', ';']
        if endswith(middle, punctuation)
          middle = middle.substr(0, middle.length - punctuation.length)
          trail = punctuation + trail
      for opening, closing in [['(', ')'], ['<', '>'], ['&lt;', '&gt;']]
        if startswith(middle, opening)
          middle = middle.substr(opening.length, middle.length - opening.length)
          lead = lead + opening
        if endswith(middle, closing) and (count_occurrances(middle, opening) == count_occurrances(middle, closing))
          middle = middle.substr(0, middle.length - closing.length)
          trail = closing + trail
      # Build URL to point to.
      url = null
      nofollow_attr = if nofollow then ' rel="nofollow"' else ''
      if simple_url_re.test(middle)
        url = middle
      else if simple_url_2_re.test(middle)
        url = "http://#{middle}"
      else if (not /:/.test(middle)) and simple_email_re.test(middle)
        [local, domain] = rsplit(middle, '@', 1)
        url = 'mailto:#{local}@#{domain}'

      if url
        trimmed = trim_url(middle)
        # Add zero-width spaces for line wrapping.
        trimmed = trimmed.replace(/([-\.\/]|.{30})/g, "$1\u200b")
        words[i] = "#{escape(lead)}<a href=\"#{url}\"#{nofollow_attr}>#{escape(trimmed)}</a>#{escape(trail)}"
      else
        words[i] = escape(word)
    else
      words[i] = escape(word)
  return words.join("")

window.urlize = urlize
