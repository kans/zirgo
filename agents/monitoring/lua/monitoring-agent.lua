--[[
Copyright 2012 Rackspace

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS-IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
--]]


local async = require('async')
local utils = require('utils')
local JSON = require('json')
local Object = require('core').Object
local fmt = require('string').format
local logging = require('logging')
local timer = require('timer')
local dns = require('dns')

local ConnectionStream = require('./lib/client/connection_stream').ConnectionStream
local constants = require('./lib/util/constants')
local misc = require('./lib/util/misc')
local States = require('./lib/states')
local stateFile = require('./lib/state_file')

function gc()
  collectgarbage('collect')
end

-- Setup GC on USR1
process:on('SIGUSR1', gc)

-- Setup GC
timer.setInterval(constants.GC_INTERVAL, gc)

local MonitoringAgent = Object:extend()

function MonitoringAgent:_queryForEndpoints(domains, callback)
  local endpoints = ''
  function iter(domain, callback)
    dns.resolve(domain, 'SRV', function(err, results)
      if err then
        logging.log(logging.ERR, 'Could not lookup SRV record from ' .. domain)
        callback()
        return
      end
      callback(nil, results)
    end)
  end
  async.map(domains, iter, function(err, results)
    local i, v
    for i, v in pairs(results) do
      endpoints = endpoints .. results[i][1].name .. ':' .. results[i][1].port
      if i ~= #results then
        endpoints = endpoints .. ','
      end
    end
    callback(nil, endpoints)
  end)
end

function MonitoringAgent:_verifyState(callback)
  if self._config == nil then
    logging.log(logging.ERR, "statefile 'config' missing or invalid")
    process.exit(1)
  end
  if self._config['monitoring_id'] == nil then
    logging.log(logging.ERR, "'id' is missing from 'config'")
    process.exit(1)
  end
  if self._config['monitoring_token'] == nil then
    logging.log(logging.ERR, "'token' is missing from 'config'")
    process.exit(1)
  end
  callback()
end

function MonitoringAgent:_loadEndpoints(callback)
  local endpoints
  local query_endpoints
  if self._config['monitoring_query_endpoints'] and
     self._config['monitoring_endpoints'] == nil then
    -- Verify that the endpoint addresses are specified in the correct format
    query_endpoints = misc.split(self._config['monitoring_query_endpoints'], '[^,]+')
    logging.log(logging.INFO, "querying for endpoints")
    self:_queryForEndpoints(query_endpoints, function(err, endpoints)
      if err then
        callback(err)
        return
      end
      self._config['monitoring_endpoints'] = endpoints
      callback()
    end)
  else
    -- Verify that the endpoint addresses are specified in the correct format
    endpoints = misc.split(self._config['monitoring_endpoints'], '[^,]+')
    if #endpoints == 0 then
      logging.log(logging.ERR, "at least one endpoint needs to be specified")
      process.exit(1)
    end
    for i, address in ipairs(endpoints) do
      if misc.splitAddress(address) == nil then
        logging.log(logging.ERR, "endpoint needs to be specified in the following format ip:port")
        process.exit(1)
      end
    end
    logging.log(logging.INFO, "using id " .. self._config['monitoring_id'])
    callback()
  end
end

function MonitoringAgent:loadStates(callback)
  async.series({
    -- Load the States
    function(callback)
      self._states:load(callback)
    end,
    -- Verify
    function(callback)
      self:_verifyState(callback)
    end,
    function(callback)
      self:_loadEndpoints(callback)
    end    
  }, callback)
end

function MonitoringAgent:connect(callback)
  local endpoints = misc.split(self._config['monitoring_endpoints'], '[^,]+')
  if #endpoints <= 0 then
    logging.log(logging.ERR, 'no endpoints')
    timer.setTimeout(misc.calcJitter(constants.SRV_RECORD_FAILURE_DELAY, constants.SRV_RECORD_FAILURE_DELAY_JITTER), function()
      process.exit(1)
    end)
    return
  end
  self._streams = ConnectionStream:new(self._config['monitoring_id'], self._config['monitoring_token'])
  self._streams:on('error', function(err)
    logging.log(logging.ERR, JSON.stringify(err))
  end)
  self._streams:createConnections(endpoints, callback)
end

function MonitoringAgent:initialize(stateDirectory, configFile)
  if not stateDirectory then stateDirectory = virgo.default_state_unix_directory end
  logging.log(logging.INFO, 'Using state directory ' .. stateDirectory)
  self._states = States:new(stateDirectory)
  self._config = virgo.config
end

function MonitoringAgent.run(options)
  if not options then options = {} end
  local agent = MonitoringAgent:new(options.stateDirectory, options.configFile)
  async.series({
    function(callback)
      agent:loadStates(callback)
    end,
    function(callback)
      agent:connect(callback)
    end
  },
  function(err)
    if err then
      logging.log(logging.ERR, err.message)
    end
  end)
end

return MonitoringAgent
