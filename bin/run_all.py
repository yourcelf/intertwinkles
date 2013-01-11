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
import sys
import select
import argparse
import subprocess
from threading import Thread

parser = argparse.ArgumentParser(description="""Run all the things.  Possible apps include: [www, proxy, etherpad, solr].  Runs everything unless you list specific apps or --exclude them.""")
# Include
parser.add_argument("include", metavar='APP', nargs='*',
        help="List of apps to run.")
# Exclude
parser.add_argument("--exclude", metavar="APP", dest="exclude", action='append',
                    help="Run everything except the given app label (one of www, proxy, etherpad, or solr). Multiple --exclude args allowed.")

args = parser.parse_args()

apps = [
    # Tag, executable, cwd (relative to this file)
    ("www", "node bin/run.js", ".."),
    ("solr", "./start.sh", "../vendor/solr/"),
    ("etherpad", "./bin/run.sh", "../vendor/etherpad-lite"),
    ("proxy", "node bin/proxy.js", ".."),
]
if args.include:
    apps = [app for app in apps if app[0] in args.include]
if args.exclude:
    apps = [app for app in apps if app[0] not in args.exclude]

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
exclude = args.exclude or []

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
                tag = "{0}{1:<5}{2}".format(
                        bcolors.HEADER,
                        app[0:5].upper(),
                        bcolors.ENDC,
                    )
                if rfd == tsk.stdout.fileno():
                    line = tsk.stdout.readline()
                    if len(line) > 0:
                        print(tag, line[:-1])
                if rfd == tsk.stderr.fileno():
                    line = tsk.stderr.readline()
                    if len(line) > 0:
                        print(
                            tag,
                            bcolors.FAIL +
                            line[:-1] + bcolors.ENDC
                        )
        if event & select.POLLHUP:
            poll.unregister(rfd)
            pollc = pollc - 1
        if pollc > 0:
            events = poll.poll()

for task in tasks:
    task.communicate()
