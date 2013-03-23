###
This module defines a helper for communicating with solr -- a wrapper for
"solr-client" (https://github.com/lbdremy/solr-node-client ).

We store our search data in mongodb, with the searchindexes collection (defined
in lib/www_schema).  These docs are then synced with solr for efficient full-text
search.
###
async       = require 'async'
solr        = require 'solr-client'
logger      = require('log4js').getLogger()
querystring = require 'querystring'

module.exports = (config) ->
  client = solr.createClient(config.solr)
  client.autoCommit = true
  schema = require('./schema').load(config)

  escape = (str) ->
    # Escape the string so that it is suitable for a solr query.  List of
    # special chars: 
    # https://lucene.apache.org/core/4_0_0/queryparser/org/apache/lucene/queryparser/classic/package-summary.html#Escaping_Special_Characters
    return str.replace(/[-+&|!(){}\[\]^"~*?:\\\/]/mg, "\\$1")

  #
  # Add a Mongo SearchIndex doc to solr.
  #
  post_search_index = (doc, done) ->
    solr_doc = {
      modified: new Date()
      sharing_group_id: doc.sharing?.group_id
      sharing_public_view_until: doc.sharing?.public_view_until
      sharing_public_edit_until: doc.sharing?.public_edit_until
      sharing_extra_viewers: doc.sharing?.extra_viewers?.join("\n")
      sharing_extra_editors: doc.sharing?.extra_editors?.join("\n")
      sharing_advertise: doc.sharing?.advertise == true
    }
    for key in ["application", "entity", "type", "url", "title", "summary", "text"]
      solr_doc[key] = doc[key]

    client.add solr_doc, (err, res) ->
      logger.error(err, res) if err? or res.responseHeader.status != 0
      done?(err, res)

  #
  # Search for things in solr, scoped by user permissions.
  #
  execute_search = (query, user, callback) ->
    query_parts = []

    if query.q # exclude falsy strings like ""
      query_parts.push(escape(query.q))
    for param in ["application", "entity", "type"]
      if query[param]?
        obj = {}
        obj[param] = query[param]
        query_parts.push(querystring.stringify(obj, "%20AND%20", ":"))

    async.waterfall [
      (done) ->
        return done(null, null) unless user?
        if user?.indexOf('@') != -1
          q = {email: user}
        else
          q = {_id: user}
        schema.User.findOne(q, (err, doc) -> done(err, doc))

      (user, done) ->
        if user?._id
          schema.Group.find {"members.user": user._id}, '_id', (err, groups) ->
            done(err, user, (escape(g._id.toString()) for g in groups))
        else
          done(null, user, [])

      (user, groups, done) ->
        # Build that sharing awesomeness query.
        sharing_or = []
        if query.public == true
          sharing_or.push("(sharing_advertise:true AND (" +
            "sharing_public_view_until:[NOW TO *] OR " +
            "sharing_public_edit_until:[NOW TO *]" +
          "))")
        if groups.length > 0
          sharing_or.push("sharing_group_id:(#{groups.join(" OR ")})")
        if user?.email?
          sharing_or.push("sharing_extra_editors:#{escape(user.email)}")
          sharing_or.push("sharing_extra_viewers:#{escape(user.email)}")
        if sharing_or.length == 0
          return done("Bad user, groups, or public.")

        query_parts.push("(#{sharing_or.join(" OR ")})")
        solr_query = client.createQuery()
        solr_query.q(query_parts.join(" AND "))
        solr_query.set("hl=true")
        if query.sort?
          solr_query.set("sort=#{querystring.stringify(escape(query.sort))}")
        done(null, solr_query)

    ], (err, solr_query) ->
      return callback(err) if err?
      client.search solr_query, (err, results) ->
        callback(err, results)

  #
  # Remove the given SearchIndex mongo doc from solr.
  #
  delete_search_index = (doc, callback) ->
    client.delete "entity", doc.entity, (err, obj) ->
      return callback(err) if err?
      return callback(obj) if obj.responseHeader.status != 0
      return callback(null)

  #
  # Delete everything from solr, and then rebuild the index from all documents
  # in the SearchIndex mongo collection.
  # NOTE: Be careful, this destroys your solr index!!
  #
  destroy_and_rebuild_solr_index = (callback) ->
    origAutoCommit = client.autoCommit
    async.waterfall [
      (done) ->
        # Delete everything
        client.deleteByQuery "*:*", done
      (result, done) ->
        # Ensure that worked.
        client.commit(done)
      (result, done) ->
        # Fetch all the things.
        schema.SearchIndex.find {}, done
      (docs, done) ->
        # Re-index all the things.
        # Disable auto-commit to improve performance.
        client.autoCommit = false
        async.map docs, post_search_index, done
      (results, done) ->
        # Commit the results.
        client.autoCommit = origAutoCommit
        client.commit(done)
    ], (err, results) ->
      logger.debug(err, results, "Done.")
      callback?(err, results)

  if config.solr?.fake_solr == true
    post_search_index = (a, cb) -> cb(null, {})
    delete_search_index = (a, cb) -> cb(null)
    execute_search = (a, cb) -> cb(null, {})

  return { client, post_search_index, execute_search, delete_search_index,
    destroy_and_rebuild_solr_index }
