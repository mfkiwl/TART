#from tartdsp import TartSPI

import os,sys,inspect
currentdir = os.path.dirname(os.path.abspath(inspect.getfile(inspect.currentframe())))
parentdir = os.path.dirname(currentdir)
parentdir2 = os.path.dirname(parentdir)
sys.path.insert(0,parentdir2)

import tartdsp
import highlevel_modes_api
import time
import json
import threading
import atexit

from flask import Flask
from flask_cors import CORS, cross_origin
from flask_jwt import JWT
from werkzeug.security import safe_str_cmp
from flask_apidoc import ApiDoc


class User(object):
    def __init__(self, id, username, password):
        self.id = id
        self.username = username
        self.password = password

    def __str__(self):
        return "User(id='%s')" % self.id

users = [
    User(1, 'admin' , 'password'),
    User(2, 'viewer', ''),
]

username_table = {u.username: u for u in users}
userid_table = {u.id: u for u in users}

def authenticate(username, password):
    user = username_table.get(username, None)
    if user and safe_str_cmp(user.password.encode('utf-8'), password.encode('utf-8')):
        return user

def identity(payload):
    user_id = payload['identity']
    return userid_table.get(user_id, None)


POOL_TIME = 1 #Seconds
# variables that are accessible from anywhere
runtime_config = {}
telescope_instance = {}
# lock to control access to variable

dataLock = threading.Lock()
# thread handler
telescope_thread = threading.Thread()

def create_app():
    app = Flask(__name__)
    CORS(app)
    doc = ApiDoc(app=app)

    app.config['SECRET_KEY'] = 'super-secret'

    def interrupt():
        global telescope_thread
        telescope_thread.cancel()

    def telescope_run():
        global runtime_config
        global telescope_instance
        global telescope_thread
        with dataLock:
          if runtime_config['mode'] == 'diag':
              runtime_config['acquire'] = False
              runtime_config['shifter'] = False
              runtime_config['counter'] = False
              runtime_config['verbose'] = False
              runtime_config['centre'] = True
              runtime_config['blocksize'] = 22
              highlevel_modes_api.run_diagnostic(telescope_instance, runtime_config)
              print 'diag'
          elif runtime_config['mode'] == 'off':
              print 'offline'
          else:
              print runtime_config['mode'], 'not implemented yet'

        # Set the next thread to happen
        telescope_thread = threading.Timer(POOL_TIME, telescope_run, ())
        telescope_thread.start()

    def telescope_init():
        # Do initialisation stuff here
        global telescope_thread
        global telescope_instance
        global runtime_config
        with dataLock:
            runtime_config['spi_speed'] = 32000000
            runtime_config['acquire'] = False
            runtime_config['shifter'] = False
            runtime_config['counter'] = False
            runtime_config['verbose'] = False
            runtime_config['centre'] = True
            runtime_config['blocksize'] = 22
            runtime_config['mode'] = 'off'
            telescope_instance = tartdsp.TartSPI(speed=runtime_config['spi_speed'])
        # Create thread
        telescope_thread = threading.Timer(POOL_TIME, telescope_run, ())
        telescope_thread.start()

    # Initiate
    telescope_init()
    # When you kill Flask (SIGTERM), clear the trigger for the next thread
    atexit.register(interrupt)
    return app

def get_config():
  global runtime_config
  return runtime_config

app = create_app()
jwt = JWT(app, authenticate, identity)

import telescope_api.views

