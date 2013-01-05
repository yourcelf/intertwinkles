winston = require 'winston'

logger = new winston.Logger
  transports: [
    new winston.transports.Console
      timestamp: false
      json: false
      level: "info"
    new winston.transports.File
      filename: 'server.log'
      timestamp: true
      json: false
      level: "info"
  ]
  levels: winston.config.syslog.levels

module.exports = logger
