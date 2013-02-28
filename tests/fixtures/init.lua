local path = require('path')
local fs = require('fs')
local string = require('string')
local JSON = require('json')
local vutils = require('virgo_utils')

local statics = require('/lua_modules').statics

local fixtures = nil

local strip_newlines = function(str)
  return str:gsub("\n", " ")
end

local load_fixtures = function(dir)
  local fixtures = {}

  for i,v in ipairs(statics) do
    if path.posix:dirname(v) == dir then
      local _, _, name = string.find(v, '(.*).json')
      if name ~= nil then
        fixtures[name] = strip_newlines(get_static(v))
      end
    end
  end
  return fixtures
end

local base = path.join('static','tests','protocol')

exports = load_fixtures(base)
exports['invalid-version'] = load_fixtures(path.join(base, 'invalid-version'))
exports['invalid-process-version'] = load_fixtures(path.join(base, 'invalid-process-version'))
exports['invalid-bundle-version'] = load_fixtures(path.join(base, 'invalid-bundle-version'))
exports['rate-limiting'] = load_fixtures(path.join(base, 'rate-limiting'))

exports.prepareJson = function(msg)
  local data = JSON.stringify(msg)
  return strip_newlines(data)
end

exports.TESTING_AGENT_ENDPOINTS = {'127.0.0.1:50041', '127.0.0.1:50051', '127.0.0.1:50061'}
return exports
