local net = require('net')
local JSON = require('json')
local fixtures = require('./')
local LineEmitter = require('line-emitter').LineEmitter
local tls = require('tls')
local timer = require('timer')

local lineEmitter = LineEmitter:new()
local port = 50041

local keyPem = [[
-----BEGIN RSA PRIVATE KEY-----
MIICXQIBAAKBgQDx3wdzpq2rvwm3Ucun1qAD/ClB+wW+RhR1nVix286QvaNqePAd
CAwwLL82NqXcVQRbQ4s95splQnwvjgkFdKVXFTjPKKJI5aV3wSRN61EBVPdYpCre
535yfG/uDysZFCnVQdnCZ1tnXAR8BirxCNjHqbVyIyBGjsNoNCEPb2R35QIDAQAB
AoGBAJNem9C4ftrFNGtQ2DB0Udz7uDuucepkErUy4MbFsc947GfENjDKJXr42Kx0
kYx09ImS1vUpeKpH3xiuhwqe7tm4FsCBg4TYqQle14oxxm7TNeBwwGC3OB7hiokb
aAjbPZ1hAuNs6ms3Ybvvj6Lmxzx42m8O5DXCG2/f+KMvaNUhAkEA/ekrOsWkNoW9
2n3m+msdVuxeek4B87EoTOtzCXb1dybIZUVv4J48VAiM43hhZHWZck2boD/hhwjC
M5NWd4oY6QJBAPPcgBVNdNZSZ8hR4ogI4nzwWrQhl9MRbqqtfOn2TK/tjMv10ALg
lPmn3SaPSNRPKD2hoLbFuHFERlcS79pbCZ0CQQChX3PuIna/gDitiJ8oQLOg7xEM
wk9TRiDK4kl2lnhjhe6PDpaQN4E4F0cTuwqLAoLHtrNWIcOAQvzKMrYdu1MhAkBm
Et3qDMnjDAs05lGT72QeN90/mPAcASf5eTTYGahv21cb6IBxM+AnwAPpqAAsHhYR
9h13Y7uYbaOjvuF23LRhAkBoI9eaSMn+l81WXOVUHnzh3ZwB4GuTyxMXXNOhuiFd
0z4LKAMh99Z4xQmqSoEkXsfM4KPpfhYjF/bwIcP5gOei
-----END RSA PRIVATE KEY-----
]]

local certPem = [[
-----BEGIN CERTIFICATE-----
MIIDXDCCAsWgAwIBAgIJAKL0UG+mRkSPMA0GCSqGSIb3DQEBBQUAMH0xCzAJBgNV
BAYTAlVLMRQwEgYDVQQIEwtBY2tuYWNrIEx0ZDETMBEGA1UEBxMKUmh5cyBKb25l
czEQMA4GA1UEChMHbm9kZS5qczEdMBsGA1UECxMUVGVzdCBUTFMgQ2VydGlmaWNh
dGUxEjAQBgNVBAMTCWxvY2FsaG9zdDAeFw0wOTExMTEwOTUyMjJaFw0yOTExMDYw
OTUyMjJaMH0xCzAJBgNVBAYTAlVLMRQwEgYDVQQIEwtBY2tuYWNrIEx0ZDETMBEG
A1UEBxMKUmh5cyBKb25lczEQMA4GA1UEChMHbm9kZS5qczEdMBsGA1UECxMUVGVz
dCBUTFMgQ2VydGlmaWNhdGUxEjAQBgNVBAMTCWxvY2FsaG9zdDCBnzANBgkqhkiG
9w0BAQEFAAOBjQAwgYkCgYEA8d8Hc6atq78Jt1HLp9agA/wpQfsFvkYUdZ1YsdvO
kL2janjwHQgMMCy/Njal3FUEW0OLPebKZUJ8L44JBXSlVxU4zyiiSOWld8EkTetR
AVT3WKQq3ud+cnxv7g8rGRQp1UHZwmdbZ1wEfAYq8QjYx6m1ciMgRo7DaDQhD29k
d+UCAwEAAaOB4zCB4DAdBgNVHQ4EFgQUL9miTJn+HKNuTmx/oMWlZP9cd4QwgbAG
A1UdIwSBqDCBpYAUL9miTJn+HKNuTmx/oMWlZP9cd4ShgYGkfzB9MQswCQYDVQQG
EwJVSzEUMBIGA1UECBMLQWNrbmFjayBMdGQxEzARBgNVBAcTClJoeXMgSm9uZXMx
EDAOBgNVBAoTB25vZGUuanMxHTAbBgNVBAsTFFRlc3QgVExTIENlcnRpZmljYXRl
MRIwEAYDVQQDEwlsb2NhbGhvc3SCCQCi9FBvpkZEjzAMBgNVHRMEBTADAQH/MA0G
CSqGSIb3DQEBBQUAA4GBADRXXA2xSUK5W1i3oLYWW6NEDVWkTQ9RveplyeS9MOkP
e7yPcpz0+O0ZDDrxR9chAiZ7fmdBBX1Tr+pIuCrG/Ud49SBqeS5aMJGVwiSd7o1n
dhU2Sz3Q60DwJEL1VenQHiVYlWWtqXBThe9ggqRPnCfsCRTP8qifKkjk45zWPcpN
-----END CERTIFICATE-----
]]

local options = {
  cert = certPem,
  key = keyPem
}

local respond = function(client, payload)

  -- skip responses to requests
  if payload.method == nil then
    return
  end

  local response_method = payload.method .. '.response'
  local response = JSON.parse(fixtures[response_method])
  local response_out = nil


  response.target = payload.source
  response.source = payload.target
  response.id = payload.id

  print("Sending response:")
  p(response)

  response_out = JSON.stringify(response)
  response_out:gsub("\n", " ")

  client:write(response_out .. '\n')
end

local send_schedule_changed = function(client)
  local request = fixtures['check_schedule.changed.request']

  print("Sending request:")
  p(JSON.parse(request))
  client:write(request .. '\n')
end

tls.createServer(options, function (client)
  client:pipe(lineEmitter)
  lineEmitter:on('data', function(line)
    local payload = JSON.parse(line)
    print("Got payload:")
    p(payload)
    respond(client, payload)
  end)

  local send_schedule_changed_timer = timer.setTimeout(2000, function()
    send_schedule_changed(client)
  end)
  local send_schedule_changed_timer = timer.setInterval(60000, function()
    send_schedule_changed(client)
  end)
end):listen(port)

print("TCP echo server listening on port " .. port)
