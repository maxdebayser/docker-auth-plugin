module(..., package.seeall)

local cjson = require'cjson'

local reserved = {
  ['and']      = true,
  ['end']      = true,
  ['in']       = true,
  ['repeat']   = true,
  ['while']    = true,
  ['break']    = true,
  ['false']    = true,
  ['local']    = true,
  ['return']   = true,
  ['do']       = true,
  ['for']      = true,
  ['nil']      = true,
  ['then']     = true,
  ['else']     = true,
  ['function'] = true,
  ['not']      = true,
  ['true']     = true,
  ['elseif']   = true,
  ['if']       = true,
  ['or']       = true,
  ['until']    = true
}

function serialize_basic(o)
	if type(o) == "number" or type(o) == "nil" or type(o) == "boolean" then
		return tostring(o)
	elseif type(o) == "string" then
		return string.format("%q", o)
	else
                -- quick and dirty hack to serialize to lua tables coming from
                -- lua-cjson
                if type(o) == "userdata" and o == cjson.null then
                  return "nil"
                end
		error("cannot serialize a " .. type(o))
	end
end

function serialize(o, name)
	local strs = {}
	if name then
		if type(name) ~= "string" then
			error("name of variable must be a string")
		end
		strs[#strs + 1] = name;
		strs[#strs + 1] = " = "
	end
	serialize_b(o, strs, name and {name})
	return table.concat(strs)
end

function arrayCopy(array)
	local b = {}
	for i, v in ipairs(array) do
		b[i] = v
	end
	return b
end

function printPath(path, strs)
		local first = true
		for i, k in ipairs(path) do
			if type(k) == "number" or type(k) == "boolean" then
				strs[#strs + 1] = "["
				strs[#strs + 1] = tostring(k)
				strs[#strs + 1] = "]"
			elseif type(k) == "string" then
				if first then
					first = false
				else
					strs[#strs + 1] = "."
				end
				strs[#strs + 1] = k
			else
				error("table key must be string or number")	
			end
		end
end

function dependencies(resolve, strs)
	for k,v in pairs(resolve) do
		printPath(k, strs)
		strs[#strs + 1] = " = "
		printPath(v, strs)
		strs[#strs + 1] = "\n"
	end
end

function serialize_b(o, strs, path, ind, visited, resolve)
	local indent = ind or ""
	visited = visited or {}
	resolve = resolve or {}
	if type(o) ~= "table" then
		strs[#strs + 1] = serialize_basic(o);
	else
		if path then
			--salva o caminho da tabela
			visited[o] = arrayCopy(path)
		else
			-- se nao tiver um path inicial, isto eh, se nao houver nome de variavel, os ciclos sao ignorados
			visited[o] = true
		end
		local num_ind = 0;
		strs[#strs + 1] = "{\n"
		for k, v in pairs(o) do
			if visited[v] then
				if path then
					--Salva o caminho para chegar no membro e o caminho para chegar ao valor referenciado por ele
					local p = arrayCopy(path)
					p[#p+1] = k
					resolve[p] = visited[v]
				end
			else
				strs[#strs + 1] = indent
				strs[#strs + 1] = "    "
				if type(k) == "number" then
					--Usa o construtor de array ate onde os numeros forem bem comportados
					if k == num_ind + 1 then
						num_ind = k
					else 
						strs[#strs + 1] = "["
						strs[#strs + 1] = k
						strs[#strs + 1] = "] = "
					end
				elseif type(k) == "boolean" then
					strs[#strs + 1] = "["
					strs[#strs + 1] = tostring(k)
					strs[#strs + 1] = "] = "
				elseif type(k) == "string" then 
          				if reserved[k] then
					  strs[#strs + 1] = "["
  					  strs[#strs + 1] = string.format("%q", k)
					  strs[#strs + 1] = "] = "
          				else 
			        	   strs[#strs + 1] = k
				        end
					strs[#strs + 1] = " = "
        			else
			    		error("name of variable must be a string")
				end
				if path then
					path[#path+1] = k
				end	
				serialize_b(v,strs, path, indent.."    ", visited, resolve)
				if path then
					path[#path] = nil
				end	
				strs[#strs + 1] = ",\n"
			end
		end
		if ind then
			strs[#strs + 1] = ind
			strs[#strs + 1] = "}"
		else
			strs[#strs + 1] = "}\n"
			-- Os ciclos sao resolvidos com atribuicoes no final
			dependencies(resolve, strs)
		end
	end
end
		
