local lp = require 'lifter_puller'
local Puller = lp.Puller
local event_type = lp.event_type
local log = require 'log'

local Parser = {}
Parser.__index = Parser

function Parser.new(xml)
    return setmetatable({puller = Puller.new(xml, false)}, Parser)
end

function Parser:get_inner_texts(...)
    log.trace('get_inner_texts', ...)
    local node_names = {}
    local ret = {}
    for _, node_name in ipairs({...}) do
        node_names[node_name] = false
    end
    local node, err = self.puller:next()
    while node do
        if node.ty == event_type.open_tag then
            if node_names[node.name] == false then
                local text_node, err = self:next_text()
                if not text_node then
                    return nil, err, ret
                end
                ret[node.name] = text_node.text
            end
        end
        node, err = self.puller:next()
        if node.ty == event_type.eof then
            break
        end
    end
    if err then
        return nil, err, ret
    end
    return ret
end

function Parser:next_text()
    local node, err = self.puller:next()
    while node and node.ty ~= event_type.text do
        node, err = self.puller:next()
    end
    if err then
        return nil, err
    end
    return node
end

---Parse the discovery XML into a description of the octopi server
---@param xml string
---@return string? @comment The DNI for this octopi
---@return string? @comment The presentation url for this octopi instance
---@return string? @comment The manufacturer string from the xml object
return function (xml)
    local ok, err
    local p = Parser.new(xml)
    local info, err, part = p:get_inner_texts('manufacturerURL', 'presentationURL', 'UDN')
    if not info then
        log.error('failed to get inner texts', err)
        info = part
    end
    local id, url, manu
    if type(info['UDN']) == 'string' then
        id = string.match(info['UDN'], 'uuid:([^%s]+)')
    end
    if type(info.presentationURL) == 'string' then
        url = info.presentationURL
    end
    if type(info.manufacturerURL) == 'string' then
        manu = info.manufacturerURL
    end
    if not id or not url or not manu then
        return nil, 'missing property', info
    end
    return id, url, manu
end
