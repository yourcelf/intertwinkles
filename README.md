# InterTwinkles

![](https://raw.github.com/yourcelf/intertwinkles/master/assets/img/inspire.png)

[![Build Status](https://travis-ci.org/yourcelf/intertwinkles.png)](https://travis-ci.org/yourcelf/intertwinkles)

InterTwinkles is a collection of tools to help small, democratic groups to make
decisions by consensus online.  The tools are designed from the ground up to
support the needs of groups like cooperatives, collectives, affinity groups and
participatory boards of directors.  The apps are all written in nodejs, and
free for you to use on your own servers.

The toolkit is under early development still.  Find the live server here:

[http://intertwinkles.org](http://intertwinkles.org)

## Installation

InterTwinkles depends on the following.  Install these first:

 * mongodb
 * redis
 * nodejs v0.8
 * java (for integration with Solr search) 
 * python >= 2.6 (required for installation and development only).
 * Various image processing and development libraries needed to compile node dependencies. On Debian/Ubuntu, these are: <tt>imagemagick libcairo2-dev libjpeg8-dev libpango1.0-dev libgif-dev build-essential g++</tt>

Once these dependencies are installed, install all the remaining dependencies
using the provided script:

    bin/install_dependencies.py

This script will download and install Solr, etherpad-lite, as well as all the
node dependencies, and will set up the configuration.

## Configuration

Configuration is found in the ``config`` directory.  The main configuration
you'll want to change if you're deploying InterTwinkles are the ports and
domains, found in ``config/domains.coffee``.  For development, you can probably
just leave the defaults.

## Scripts

 * ``bin/run.js``: Run the InterTwinkles web process.
 * ``bin/proxy.js``: Run a light-weight proxy server (built with node-http-proxy) to resolve the configured domains to the backend instances.
 * ``bin/set_deploy_permissions.py``: Sets the permissions for all directories that need to be writable by a web server user (e.g. www-data).  Run this on production servers after installation to give the needed access.
 * ``bin/run_all.py``: This script runs the bundled Solr and etherpad-lite servers, as well as the InterTwinkles web process and a proxy server which maps the configured domains to the backend servers.  It's mostly useful for development; in production you'll want to run each server separately using supervisord or similar.
 * ``vendor/solr/start.sh``: This script launches the bundled Solr server. Some InterTwinkles apps can't run without it.

## Join us

Join us over at [project.intertwinkles.org](http://project.intertwinkles.org)!  Follow [@intertwinkles](https://twitter.com/intertwinkles).

Read our blog at [blog.intertwinkles.org](http://blog.intertwinkles.org).


## License

InterTwinkles is published under the terms of the two clause BSD License, see the
COPYING file. Although the BSD License does not require you to share any
modifications you make to the source code, you are very much encouraged and
invited to contribute back your modifications to the community, preferably in a
GitHub fork (fork it, modify it then create a pull request describing your changes).
