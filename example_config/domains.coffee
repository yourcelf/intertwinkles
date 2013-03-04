#
# Configuration of front-end domains, and back-end ports. These are settings
# you'll want to change in deployment so that absolute URLs refer to the
# locations in front of any proxy servers, and back-end ports don't conflict.
#

module.exports = {
  # Port on which app is listening. (`bin/run.js`).
  base_port: 9000
  # Port on which the optional proxy server listens (`bin/proxy.js`).
  proxy_port: 8443
  # Port on which the optional redirect server listens (`bin/redirect_server.js`).
  redirect_port: 8080
  # The URL clients should use when connecting, which is proxied to the
  # listening port (e.g. `dev.intertwinkles.org`)
  front_end_url: "http://localhost:9000"
  # Short URL base should be the path to a shortener that will redirect to
  # {front_end_url}/r/.  If you don't have a short URL mapped, just use
  # {front_end_url}/r/, (e.g. "http://localhost:9000/r/").
  short_url_base: "http://localhost:9000/r/"
  # Front end URL for the Etherpad instance.  Other etherpad params, including
  # the port on which etherpad will listen, are configured in
  # `config/etherpad/settings.json`.  Etherpad reads that config file.
  etherpad_url: "http://localhost:9001"
  # Domain field for etherpad session cookie. Should be readable by both the
  # front_end_url's domain and etherpad_url's domain -- e.g. same domain, or
  # with prefixed "." for subdomains.  See
  # https://en.wikipedia.org/wiki/HTTP_cookie#Domain_and_Path
  etherpad_cookie_domain: "localhost"
  # Domain for the alpha warning cookie.
  alpha_cookie_domain: "localhost"
  # Email address for the 'From' header in server-generated emails
  from_email: "notices@example.com"
}
