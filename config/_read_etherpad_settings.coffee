#
# This is a trick to parse etherpad's settings file within its context.
# See http://stackoverflow.com/a/9946809
#
fs = require 'fs'
vm = require 'vm'

# Since etherpad uses non-standard json, we have to parse it as javascript.
settingsStr = fs.readFileSync __dirname + '/etherpad/settings.json'
try
  module.exports = vm.runInContext("exports = " + settingsStr, vm.createContext(), "settings.json")
catch e
  console.error("There was an error parsing config/etherpad/settings.json: " + e.message)
  process.exit(1)
