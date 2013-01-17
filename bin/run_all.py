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
import tty
import select
import termios
import argparse
import subprocess

parser = argparse.ArgumentParser(description="""Run all the things.  Possible apps include: [www, proxy, etherpad, solr].  Runs everything unless you list specific apps or --exclude them.""")
# Include
parser.add_argument("include", metavar='APP', nargs='*',
        help="List of apps to run.")
# Exclude
parser.add_argument("--exclude", metavar="APP", dest="exclude", action='append',
                    help="Run everything except the given app label (one of www, proxy, etherpad, or solr). Multiple --exclude args allowed.")


class bcolors:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'

class OutputTagger(object):
    def __init__(self):
        self.task_map = {}
        self.pollc = 0
        self.poll = select.poll()
        self.apps = {}

    def start(self, app, cmd, cwd):
        print(bcolors.OKGREEN + "starting", app + bcolors.ENDC)
        proc = subprocess.Popen(cmd.split(),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                cwd=os.path.join(os.path.dirname(__file__), cwd)
        )
        self.task_map[app] = proc
        self.apps[app] = (cmd, cwd)

        self.poll.register(proc.stdout, select.POLLIN | select.POLLHUP)
        self.poll.register(proc.stderr, select.POLLIN | select.POLLHUP)
        self.pollc += 2

    def poll_output(self):
        events = self.poll.poll()
        while self.pollc > 0 and len(events) > 0:
            for event in events:
                (rfd,event) = event
                if event & select.POLLIN:
                    for (app, tsk) in self.task_map.iteritems():
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
                    self.poll.unregister(rfd)
                    self.pollc -= 1 
                if self.pollc > 0:
                    events = self.poll.poll()

    def restart(self, app):
        if app in self.apps:
            self.kill(app)
            self.start(app, *self.apps[app])

    def kill(self, app):
        if app in self.apps:
            print(bcolors.OKGREEN + "killing", app + bcolors.ENDC)
            proc = self.task_map.pop(app, None)
            proc.kill()

    def killall(self):
        for app in self.apps:
            self.kill(app)

    def block(self):
        for key,proc in self.task_map.iteritems():
            proc.communicate()

def main(apps):
    args = parser.parse_args()
    include = args.include or apps.keys()
    apps = dict([(k, v) for k,v in apps.iteritems() if k in include])
    if args.exclude:
        for k in args.exclude:
            apps.pop(k, None)

    tagger = OutputTagger()
    for key, (exe, cwd) in apps.iteritems():
        tagger.start(key, exe, cwd)
    try:
        tagger.poll_output()
    except KeyboardInterrupt:
        tagger.killall()

    # Read last exit status if any.
    tagger.block()

if __name__ == "__main__":
    apps = {
        # Tag, executable, cwd (relative to this file)
        "www": ("node bin/run.js", ".."),
        "solr": ("./start.sh", "../vendor/solr/"),
        "etherpad": ("./bin/run.sh", "../vendor/etherpad-lite"),
        "proxy": ("node bin/proxy.js", ".."),
    }
    main(apps)
