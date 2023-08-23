local ngx = ngx
local isempty = require 'isempty'
local isarray = require 'isarray'
local http = require 'resty.http'
local cjson = require 'cjson.safe'

---@param endpoint string
---@param ReqBody table
---@return string?
local function sendTo(endpoint, ReqBody)
    ngx.log(ngx.INFO, 'Send with endpoint: ', endpoint)
    local Res, err = http.new():request_uri(
        endpoint,
        {
            method = 'POST',
            headers = { ['Content-Type'] = 'application/json' },
            body = cjson.encode(ReqBody),
        }
    )
    return err and ngx.log(ngx.ERR, err) or Res.body
end

---@return table
local function getNodes()
    local nodes = {}
    for i, _ in ipairs(ngx.shared.nodes:get_keys()) do
        table.insert(nodes, ngx.shared.nodes:get(tostring(i)))
    end
    return nodes
end

---@param ReqBody table
---@return string?
local function routeTo(ReqBody)
    if ReqBody.method == 'eth_call' or ReqBody.method == 'eth_sendRawTransaction' then
        for _, endpoint in ipairs(getNodes()) do
            local res = sendTo(endpoint, ReqBody)
            if res then return res end
        end
    end
    return sendTo(ngx.var.node, ReqBody)
end

---@return table?
local function getReqBody()
    local ReqBody = cjson.decode(ngx.req.get_body_data() or '')
    if type(ReqBody) ~= 'table' or isempty(ReqBody) then
        ngx.say('Wrong input')
        return ngx.exit(400)
    end
    return ReqBody
end

http:set_timeouts(5000, 5000, 5000)
cjson.encode_empty_table_as_object(false)

local M = {}

function M.proxyTo()
    local ReqBody = getReqBody() or {}
    if isarray(ReqBody) then
        local Response = {}
        for i, Req in ipairs(ReqBody) do
            local res = routeTo(Req)
            if res then Response[i] = cjson.decode(res) end
        end
        ngx.say(cjson.encode(Response))
    else
        ngx.say(routeTo(ReqBody))
    end
end

function M.updateNodes()
    local Nodes = ngx.shared.nodes
    Nodes:flush_all()
    Nodes:flush_expired()
    for key, value in pairs(getReqBody() or {}) do
        Nodes:set(tostring(key), value)
    end
    return ngx.exit(200)
end

return M
