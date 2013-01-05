config  = require './config'

task 'runserver', 'Run the server.',  ->
  server = require './lib/server'
  require('./lib/server').start(config)

task 'resave', 'Resave all ideas, to recreate their images.', (options) ->
  mongoose = require 'mongoose'
  db = mongoose.connect(
    "mongodb://#{config.dbhost}:#{config.dbport}/#{config.dbname}"
  )
  models = require('./lib/schema')
  models.Idea.find {}, (err, docs) ->
    count = docs.length
    exitCode = 0
    for doc in docs
      doc.incImageVersion()
      doc.save (err) ->
        count--
        if err?
          exitCode = 1
          console.log(count, err)
        else
          console.log(count)
        if count == 0
          process.exit(exitCode)
