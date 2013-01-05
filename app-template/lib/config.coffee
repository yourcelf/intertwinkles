fs = require 'fs'

try
    config = JSON.parse(fs.readFileSync(__dirname + '/../config.json', 'utf-8'))
catch e
    console.log "ERROR: Missing config file", e
    process.exit(1)

module.exports = config
