fs = require 'fs'
vm = require 'vm'

# Since etherpad uses non-standard json, we have to parse it as javascript.
# This strategy lifted from etherpad's own.
settingsStr = fs.readFileSync __dirname + '/settings.json'
try
  module.exports = vm.runInContext("exports = " + settingsStr, vm.createContext(), "settings.json")
catch e
  console.error("There was an error parsing config/etherpad/settings.json: " + e.message)
  process.exit(1)
