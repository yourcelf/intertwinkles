#!/usr/bin/env python
"""
Set the file permissions appropriately for deployment.  Call with the argument
of the webserver user (e.g. 'www-data') that should have permissions to uploads
and log files.
"""
import os
import sys
import subprocess

server_writable_directories = [
    "vendor/solr/apache-solr-4.0.0/example/solr/collection1/data/",
    "vendor/solr/apache-solr-4.0.0/example/solr-webapp/",
    "lib/dotstorm/assets/dotstorm/uploads/",
    "lib/www/assets/group_logos/",
    "lib/www/assets/user_icons/",
]
BASE = os.path.join(os.path.dirname(__file__), "..")

def set_permissions(user):
    for path in server_writable_directories:
        print user, path
        if not os.path.exists(path):
            os.makedirs(path)
        subprocess.check_call(["chown", "-R", user, os.path.join(BASE, path)])

if __name__ == "__main__":
    try:
        target_user = sys.argv[1]
    except IndexError:
        print "Missing required parameter `target user`."
        print "Usage: set_deploy_permissions.py [username]"
        sys.exit(1)
    set_permissions(target_user)
