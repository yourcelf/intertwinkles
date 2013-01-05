route = (app, host) ->
  app.get '/auth/logout', (req, res) ->
      delete req.session.user
      req.flash('info', 'You are now logged out.')
      res.redirect('/')
    
  app.post '/auth/verify', (req, res) ->
    success = (answer) ->
      # Logged in!
      req.flash('info', "You are now logged in as #{answer.email}.")
      req.session.user =
        email: answer.email
      res.send JSON.stringify answer
    error = (answer) ->
      # Error logging in.
      delete req.session.user
      req.flash('error', "Bad computer. Error logging in.  The robot says: #{ answer.reason }")
      res.statusCode = 401
      res.send "Oh noes! #{JSON.stringify answer}"
    require('./browserid').verify(req.body.assertion, host, success, error)

module.exports = { route }
