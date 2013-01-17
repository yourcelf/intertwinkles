# InterTwinkles

![](https://github.com/yourcelf/intertwinkles/blob/master/lib/www/assets/www/img/inspire.png)

InterTwinkles is a collection of tools to help small, democratic groups to make
decisions by consensus online.  The tools are designed from the ground up to
support the needs of groups like cooperatives, collectives, affinity groups and
participatory boards of directors.  The apps are all written in nodejs, and
free for you to use on your own servers.

The toolkit is under early development still, but a demo can be found here:

[http://dev.intertwinkles.org](http://dev.intertwinkles.org) (Data is periodically deleted from that installation, so use it for testing only!)

## Installation

InterTwinkles depends on the following.  Install these first:

 * mongodb
 * redis
 * nodejs v0.8
 * java (for integration with Solr search) 
 * python >= 2.6 (required for installation and development only).

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

## License
Copyright (c) 2013, Charlie DeTar
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met: 

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer. 
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution. 

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
