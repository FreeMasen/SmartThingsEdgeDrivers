local api = require 'api'
local username = assert(os.getenv('UDM_USER'), 'No UDM_USER env variable')
local password = assert(os.getenv('PASSWORD'), 'No UDM_USER env variable')
local client = assert(os.getenv('UDM_TARGET'), 'No UDM_TARGET env variable')
local ip = os.getenv('UDM_IP') or '192.168.1.1'
local cookie, xsrf = assert(api.login(ip, username, password))
api.check_for_presence(ip, client, cookie, xsrf)
