#
# Configuration of ports and domains to use for the express app and proxy
# server.
#
module.exports = {
  # Port on which app is listening. (e.g. `bin/run.js`).
  base_port: 9000
  # The URL clients should use when connecting, which is proxied to the
  # listening port (e.g. `dev.intertwinkles.org`)
  front_end_url: "http://localhost:9000"
  # Short URL base should be the path to a shortener that rewrites to
  # {front_end_url}/r/.  If you don't have a short URL mapped, just use
  # {front_end_url}/r/.
  short_url_base: "http://localhost:9000/r/"
  # Front end URL for the Etherpad instance.  Other etherpad params configured
  # in `config/etherpad/settings.json`.
  etherpad_url: "http://localhost:9001"
  # Domain field for etherpad session cookie. Should be readable by both the
  # front end and etherpad domain -- e.g. same domain, or with prefixed "." for
  # subdomains.  See https://en.wikipedia.org/wiki/HTTP_cookie#Domain_and_Path
  etherpad_cookie_domain: "localhost"
  # Domain for the alpha warning cookie.
  alpha_cookie_domain: "localhost"
  # Email address for the 'From' header in server-generated emails
  from_email: "notices@dev.intertwinkles.org"
  # Port on which the included proxy listens (e.g. `bin/proxy.js`).
  proxy_port: 8080
}
