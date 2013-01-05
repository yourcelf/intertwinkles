Dotstorm
========

.. image:: http://dotstorm.byconsens.us/img/icon96.png
    :alt: dotstorm logo
    :target: http://dotstorm.byconsens.us

Dotstorm is a real-time, collaborative sticky-note style brainstorming tool.
Ideas can be drawn, photographed, or typed in, and then sorted, tagged, voted
on and embedded into other websites or blogs.

Try it out here:  http://dotstorm.byconsens.us

Dotstorm is written in coffeescript, using node.js, socket.io, and the other dependencies mentioned in `package.json <https://github.com/yourcelf/dotstorm/blob/master/package.json>`_.  

Development
~~~~~~~~~~~

Download the code by cloningthe repository.  Install node >= 0.6, and navigate to the project directory.  Depends on ``mongodb``, ``imagemagick``, and ``libcairo``.  Install node dependencies using::

    npm install

Run the development server (defaults to `localhost:8000`) using::

    cake runserver

Run tests with::

    npm test

Have fun, and please contribute any issues or forks here on the github issue tracker.

Author
~~~~~~

By Charlie DeTar, cfd@media.mit.edu.

License
~~~~~~~

`License: AGPLv3 <https://www.gnu.org/licenses/agpl-3.0.html>`_.

If you need have other licensing needs, please talk to me, I'd be happy to
discuss!
