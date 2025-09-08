#!/usr/bin/lua

local Dictionary = {}

function Dictionary:new()
  local dictionary = {}
  setmetatable(dictionary, self)
  self.__index = self
  return dictionary
end

function Dictionary:add(name, label, addr)
  self[#self + 1] = {
    name = name,
    label = label,
    addr = addr,
  }
end

function Dictionary:latest()
  return self[#self]
end

function Dictionary:find(name)
  local i = #self
  while i > 0 do
    if self[i].name == name then
      return self[i]
    end
    i = i - 1
  end
  return nil
end

-- Returns address or nil if missing
function Dictionary:findAddr(name)
  local dictEntry = self:find(name)
  if dictEntry then
    return dictEntry.addr
  else
    return nil
  end
end

-- Returns the dictionary-entry for the given XT.
-- TODO: This should be instead be found by looking at dataspace metadata.
function Dictionary:findXt(xt)
  local i = #self
  while i > 0 do
    if self[i].addr == xt then
      return self[i]
    end
    i = i - 1
  end
  return nil
end

function Dictionary:addrName(addr)
  local maybeDict = self:findXt(addr)
  if not maybeDict then
    return nil
  end
  return maybeDict.name
end

function Dictionary:addrLabel(addr)
  local maybeDict = self:findXt(addr)
  if not maybeDict then
    return nil
  end
  return maybeDict.label
end

return Dictionary
