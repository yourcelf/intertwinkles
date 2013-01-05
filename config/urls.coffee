# This file configures the URLs that are exposed to the client.  If you are not
# proxying, you'll need to ensure that the ports here match the ports for each
# app.

base_url = "http://localhost"
module.exports = {
  short_url_base: "http://localhost:9000/r/",
  home: "#{base_url}:9000"
  resolve: "#{base_url}:9001"
  firestarter: "#{base_url}:9002"
  dotstorm: "#{base_url}:9003"
  twinklepad: "#{base_url}:9004"
  etherpad: "#{base_url}:9005"
  ALPHA_COOKIE_DOMAIN: "localhost"
}
