local router = require'router'
local cjson  = require'cjson'
local re     = require're'
local lpeg   = require'lpeg'
local ser    = require'serialize'

local b64=require'base64'

local fmt = string.format

function newAuthController()

  local meta = {
    __call = function(self, user, path, params, reqBody)
      for _, entry in ipairs(self.handlers) do
        local m = { lpeg.match(entry.patt, path) }
        if #m > 0 then
           return entry.handler(user, params, reqBody, table.unpack(m))
        end
      end
      return self:defaultErr(path)
    end
  }

  local obj = {
    handlers = {};

    add = function(self, path_patt, handler)
      table.insert(self.handlers, { patt = re.compile(path_patt), handler = handler})
    end;

    defaultErr = function(self, path)
      local err = fmt("Request '%s' is not whitelisted.", path)
      return cjson.encode({
        Allow = false,
        Msg   = "The request authorization failed. "..err,
        Err   = err
      })
    end;

  }

  setmetatable(obj, meta)
  return obj

end

local authControl = newAuthController()

function allow()
  return cjson.encode({ Allow = true})
end

function deny(reason)
  return cjson.encode({
    Allow = false,
    Msg   = "The request authorization failed. "..(reason or ""),
    Err   = "Not authorized" 
  })
end

authControl:add("'/containers/json'!.+", allow)
authControl:add("'/info'!.+", allow)
authControl:add("'/version'!.+", allow)
authControl:add("'/images/json'!.+", allow)

authControl:add("'/build'!.", allow)

authControl:add("'/images/create'!.", allow)

--docker history
authControl:add("'/images/'{(!'/history' . )+}'/history'!.", function(user, params, reqBody, image)
  print("image =", image)
  return allow()
end)

-- docker inspect
authControl:add("'/containers/'{(!'/json' . )+}'/json'!.", function(user, params, reqBody, image)
  print("container =", image)
  return allow()
end)

authControl:add("'/containers/create'!.", function(user, params, reqBody, image)
  print("container name =", params.name)
  print("req body ", reBody)
  for k,v in pairs(reqBody) do print(k,v) end
  return allow()
end)

--docker attach, called from run
authControl:add("'/containers/'{(!'/attach' . )+}'/attach'!.", function(user, params, reqBody, containerID)
  print("container =", containerID)
  return allow()
end)

--docker start, called from run
authControl:add("'/containers/'{(!'/start' . )+}'/start'!.", function(user, params, reqBody, containerID)
  print("container =", containerID)
  return allow()
end)

authControl:add("'/containers/'{(!'/wait' . )+}'/wait'!.", function(user, params, reqBody, containerID)
  print("container =", containerID)
  return allow()
end)

authControl:add("'/containers/'{(!'/resize' . )+}'/resize'!.", function(user, params, reqBody, containerID)
  print("container =", containerID)
  return allow()
end)

local app = router.new()

app:use(function(req, res, _next)
  _next()
  res.headers['Content-type'] = 'application/json'
  if res.status == 404 then
    res:resetbody()
    res:write('"not found"')
  end
end)

app:post("'/Plugin.Activate'!.+", function(req,res)
  res:write(cjson.encode({ Implements = {'authz' }}))
end)

local path_pattern = re.compile("'/'{'v1.22'}{[^?]+}'?'?{| ({|{[^=&]+}'='{[^=&]+}|}'&'? )+ |}?")


app:post("'/AuthZPlugin.AuthZReq'!.+", function(req,res)

  local request_ok = false
  if req.POST.post_data then
    print("post data = ", req.POST.post_data)

    local authParams = cjson.decode(req.POST.post_data)
    if authParams.RequestBody then
      authParams.RequestBody = cjson.decode(b64.decode(authParams.RequestBody))
    end
    
    if authParams then
      request_ok = true
      local user = authParams.User or authParams.RequestHeaders.User
      if not user then
        res:write(cjson.encode({
          Allow = false,
          Msg   = "The request authorization failed. No User",
          Err   = "No User."
        }))
      else
        local apiVersion, path, _params = re.match(authParams.RequestUri, path_pattern)
        local params = {}
        -- there must be a way to do this directly in lpeg.re
        for _,pair in ipairs(_params or {}) do params[pair[1]] = pair[2] end
        res:write(authControl(user, path, params, authParams.RequestBody))
      end
    end
    
  end
  if not request_ok then
    res:write(cjson.encode({
      Allow = false,
      Msg   = "The request authorization failed. Invalid request",
      Err   = "Invalid request."
    }))
  end
end)

app:post("'/AuthZPlugin.AuthZRes'!.+", function(req,res)
  print("auth res")
  local authParams = cjson.decode(req.POST.post_data)
  if authParams.ResponseBody then
    authParams.ResponseBody = cjson.decode(b64.decode(authParams.ResponseBody))
  end

  print(ser.serialize(authParams))
    
  res:write(cjson.encode({ Allow = true}))
end)

return app
