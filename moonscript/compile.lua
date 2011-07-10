module("moonscript.compile", package.seeall)
local util = require("moonscript.util")
local data = require("moonscript.data")
local dump = require("moonscript.dump")
require("moonscript.compile.format")
require("moonscript.compile.line")
require("moonscript.compile.value")
local ntype = data.ntype
local concat, insert = table.concat, table.insert
local Line
Line = (function(_parent_0)
  local _base_0 = {
    _append_single = function(self, item)
      if util.moon.type(item) == Line then
        local _item_0 = item
        for _index_0=1,#_item_0 do
          local value = _item_0[_index_0]
          self:_append_single(value)
        end
      else
        insert(self, item)
      end
      return nil
    end,
    append_list = function(self, items, delim)
      for i = 1, #items do
        self:_append_single(items[i])
        if i < #items then
          insert(self, delim)
        end
      end
    end,
    append = function(self, ...)
      local _item_0 = { ... }
      for _index_0=1,#_item_0 do
        local item = _item_0[_index_0]
        self:_append_single(item)
      end
      return nil
    end,
    render = function(self)
      local buff = {  }
      for i = 1, #self do
        local c = self[i]
        insert(buff, (function()
          if util.moon.type(c) == Block then
            return c:render()
          else
            return c
          end
        end)())
      end
      return concat(buff)
    end
  }
  _base_0.__index = _base_0
  local _class_0 = setmetatable({ __init = function(self, ...)
      if _parent_0 then
        return _parent_0.__init(self, ...)
      end
    end }, { __index = _base_0, __call = function(mt, ...)
      local self = setmetatable({}, _base_0)
      mt.__init(self, ...)
      return self
    end })
  _base_0.__class = _class_0
  return _class_0
end)()
local Block_
Block_ = (function(_parent_0)
  local _base_0 = {
    line_table = function(self) return self._posmap end,
    set = function(self, name, value) self._state[name] = value end,
    get = function(self, name) return self._state[name] end,
    declare = function(self, names)
      local undeclared = (function()
        local _moon_0 = {}
        local _item_0 = names
        for _index_0=1,#_item_0 do
          local name = _item_0[_index_0]
          if type(name) == "string" and not self:has_name(name) then
            table.insert(_moon_0, name)
          end
        end
        return _moon_0
      end)()
      local _item_0 = undeclared
      for _index_0=1,#_item_0 do
        local name = _item_0[_index_0]
        self:put_name(name)
      end
      return undeclared
    end,
    put_name = function(self, name) self._names[name] = true end,
    has_name = function(self, name) return self._names[name] end,
    free_name = function(self, prefix, dont_put)
      prefix = prefix or "moon"
      local searching = true
      local name, i = nil, 0
      while searching do
        name = concat({ "", prefix, i }, "_")
        i = i + 1
        searching = self:has_name(name)
      end
      if not dont_put then
        self:put_name(name)
      end
      return name
    end,
    init_free_var = function(self, prefix, value)
      local name = self:free_name(prefix, true)
      self:stm({ "assign", { name }, { value } })
      return name
    end,
    mark_pos = function(self, node) self._posmap[#self._lines + 1] = node[-1] end,
    add_line_text = function(self, text)
      self.line_offset = self.line_offset + 1
      return insert(self._lines, text)
    end,
    add = function(self, line)
      local t = util.moon.type(line)
      if t == "string" then
        return self:add_line_text(line)
      elseif t == Block then
        return self:add(self:line(line))
      elseif t == Line then
        return self:add_line_text(line:render())
      else
        return error("Adding unknown item")
      end
    end,
    push = function(self) self._names = setmetatable({  }, { __index = self._names }) end,
    pop = function(self) self._names = getmetatable(self._names).__index end,
    render = function(self)
      local flatten
      flatten = function(line)
        if type(line) == "string" then
          return line
        else
          return line:render()
        end
      end
      local header = flatten(self.header)
      if #self._lines == 0 then
        local footer = flatten(self.footer)
        return(concat({ header, footer }, " "))
      end
      local body = pretty(self._lines, indent_char:rep(self.indent))
      return concat({ header, body, indent_char:rep(self.indent - 1) .. (function()
          if self.next then
            return self.next:render()
          else
            return flatten(self.footer)
          end
        end)() }, "\n")
    end,
    block = function(self, header, footer) return Block(self, header, footer) end,
    line = function(self, ...)
      do
        local _with_0 = Line()
        _with_0:append(...)
        return _with_0
      end
    end,
    is_stm = function(self, node) return line_compile[ntype(node)] ~= nil end,
    is_value = function(self, node)
      local t = ntype(node)
      return value_compile[t] ~= nil or t == "value"
    end,
    name = function(self, node) return self:value(node) end,
    value = function(self, node, ...)
      if type(node) ~= "table" then
        return(tostring(node))
      end
      local fn = value_compile[node[1]]
      if not fn then
        error("Failed to compile value: " .. dump.value(node))
      end
      self:mark_pos(node)
      return fn(self, node, ...)
    end,
    values = function(self, values, delim)
      delim = delim or ', '
      return concat((function()
        local _moon_0 = {}
        local _item_0 = values
        for _index_0=1,#_item_0 do
          local v = _item_0[_index_0]
          table.insert(_moon_0, self:value(v))
        end
        return _moon_0
      end)(), delim)
    end,
    stm = function(self, node, ...)
      local fn = line_compile[ntype(node)]
      if not fn then
        if has_value(node) then
          return self:stm({ "assign", { "_" }, { node } })
        else
          return self:add(self:value(node))
        end
      else
        local out = fn(self, node, ...)
        if out then
          return self:add(out)
        end
      end
    end,
    ret_stms = function(self, stms, ret)
      if not ret then
        ret = returner
      end
      local i = 1
      while i < #stms do
        self:stm(stms[i])
        i = i + 1
      end
      local last_exp = stms[i]
      if last_exp then
        if cascading[ntype(last_exp)] then
          self:stm(last_exp, ret)
        elseif self:is_value(last_exp) then
          local line = ret(stms[i])
          if self:is_stm(line) then
            self:stm(line)
          else
            error("got a value from implicit return")
          end
        else
          self:stm(last_exp)
        end
      end
      return nil
    end,
    stms = function(self, stms, ret)
      if ret then
        self:ret_stms(stms, ret)
      else
        local _item_0 = stms
        for _index_0=1,#_item_0 do
          local stm = _item_0[_index_0]
          self:stm(stm)
        end
      end
      return nil
    end
  }
  _base_0.__index = _base_0
  local _class_0 = setmetatable({ __init = function(self, parent, header, footer)
      self.parent, self.header, self.footer = parent, header, footer
      if not self.header then
        self.header = "do"
      end
      if not self.footer then
        self.footer = "end"
      end
      self.line_offset = 1
      self._lines = {  }
      self._posmap = {  }
      self._names = {  }
      self._state = {  }
      if self.parent then
        self.indent = self.parent.indent + 1
        setmetatable(self._state, { __index = self.parent._state })
        return setmetatable(self._names, { __index = self.parent._names })
      else
        self.indent = 0
      end
    end }, { __index = _base_0, __call = function(mt, ...)
      local self = setmetatable({}, _base_0)
      mt.__init(self, ...)
      return self
    end })
  _base_0.__class = _class_0
  return _class_0
end)()
local RootBlock
RootBlock = (function(_parent_0)
  local _base_0 = { render = function(self) return concat(self._lines, "\n") end }
  _base_0.__index = _base_0
  if _parent_0 then
    setmetatable(_base_0, getmetatable(_parent_0).__index)
  end
  local _class_0 = setmetatable({ __init = function(self, ...)
      if _parent_0 then
        return _parent_0.__init(self, ...)
      end
    end }, { __index = _base_0, __call = function(mt, ...)
      local self = setmetatable({}, _base_0)
      mt.__init(self, ...)
      return self
    end })
  _base_0.__class = _class_0
  return _class_0
end)(Block_)
Block = Block_
tree = function(tree)
  local scope = RootBlock()
  local _item_0 = tree
  for _index_0=1,#_item_0 do
    local line = _item_0[_index_0]
    scope:stm(line)
  end
  return scope:render(), scope:line_table()
end
