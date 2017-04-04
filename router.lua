--[[
   Shameless nodejs express rip-off
--]]

module(..., package.seeall)
local request = require'wsapi.request'
local response = require'wsapi.response'
local re = require're'
local lpeg = require'lpeg'

function e_type(obj)
  return lpeg.type(obj) or type(obj)
end

local msg404 = [[
<html>
  <head>
    <title>Lua HTTP middleware</title>
  </head>
  <body>
    <H1>Not found</H1>
  </body>
</html>
]]

function new() 

  local meta = {
    __call = function(self, wsapi_env)
      
      local req = request.new(wsapi_env) 
      local headers = { ["Content-type"] = "text/html" }
      local res = response.new(200, headers)

      -- monkey path wsapi
      res.resetbody = function(self)
        self.length = 0
        self.body = {}
      end

      local _next = nil
      local i = 0
      _next = function()
        i = i + 1
        if i <= #self.handlerChain then
          self.handlerChain[i](req, res, _next)
        else
          res.status = 404
          res:write(msg404)
        end
      end

      _next() 
      return res:finish()

    end
  }

  function method_handler(method)
    return function (self, path, handler)
      self:use(
        path,
        function(req, res, _next, cap)
           if req.method == method then
             return handler(req, res, cap)
           else
             _next()
           end
        end
      )
    end
  end

  local obj = {
 
    handlerChain = {};

    use = function (self, ...)
      local args = {...}
      if #args == 2 then
        local pat = re.compile(args[1])
        
        table.insert(self.handlerChain, function(req, res, _next)
          local m = {lpeg.match(pat, req.path_info)}
          if #m > 0 then
            args[2](req, res, _next, table.unpack(m))
          else
            _next()
          end
        end)
        
      else
        table.insert(self.handlerChain, args[1])
      end
    end;

    all = function (self, path, handler)
      self:use(
        path,
        function(req, res, _next, cap)
           return handler(req, res, cap)
        end
      )
    end;

    get = method_handler('GET');
    post = method_handler('POST');
    put = method_handler('PUT');
    delete = method_handler('DELETE');
  }

  obj.run = function(...)
     return obj(...)
  end

  setmetatable(obj, meta)
  return obj

end
