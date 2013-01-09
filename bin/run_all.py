#!/usr/bin/env python
"""
This script runs the node server, as well as Solr, etherpad, and the proxy
server all at once.  Logs for each are prepended with a tag indicating 
which thing is logging.

This is useful for development; though in production you'll
probably want to run each part separately via supervisord or similar.
"""
from __future__ import print_function
import os
import subprocess
import select
from threading import Thread

apps = [
    # Tag, executable, cwd (relative to this file)
    ("INTRTW ", "node bin/run.js", ".."),
    ("SOLR   ", "./start.sh", "../vendor/solr/"),
    ("ETHER  ", "./bin/run.sh", "../vendor/etherpad-lite"),
    ("PROXY  ", "node bin/proxy.js", ".."),
]

class bcolors:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'

tasks = []
pollc = 0
poll = select.poll()

for app, cmd, cwd in apps:
    print(bcolors.OKGREEN + "starting", app + bcolors.ENDC)
    tsk = subprocess.Popen(cmd.split(),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=os.path.join(os.path.dirname(__file__), cwd)
    )
    tasks.append(tsk)

    poll.register(tsk.stdout,select.POLLIN | select.POLLHUP)
    poll.register(tsk.stderr,select.POLLIN | select.POLLHUP)
    pollc += 2


events = poll.poll()
while pollc > 0 and len(events) > 0:
    for event in events:
        (rfd,event) = event
        if event & select.POLLIN:
            for (app, cmd, cwd), tsk in zip(apps, tasks):
                if rfd == tsk.stdout.fileno():
                    line = tsk.stdout.readline()
                    if len(line) > 0:
                        print(app, line[:-1])
                if rfd == tsk.stderr.fileno():
                    line = tsk.stderr.readline()
                    if len(line) > 0:
                        print(
                            app,
                            bcolors.WARNING +
                            line[:-1] + bcolors.ENDC
                        )
        if event & select.POLLHUP:
            poll.unregister(rfd)
            pollc = pollc - 1
        if pollc > 0:
            events = poll.poll()

for task in tasks:
    task.communicate()
