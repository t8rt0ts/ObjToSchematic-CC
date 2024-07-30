local lib,metatables = {},{}
local expect,range = require("cc.expect").expect,require("cc.expect").range

local osepoch,osqe,ospe = os.epoch,os.queueEvent,os.pullEvent
local nosleeptimer = osepoch("UTC") + 5000
local function nosleep()
    if osepoch("UTC") > nosleeptimer then
        osqe("nosleep")
        ospe()
        nosleeptimer = osepoch("UTC") + 5000
    end
    -- osqe("nosleep")
    -- ospe()
end

local tags = {
    ["END"] = 0,
    BYTE = 1,
    SHORT = 2,
    INT = 3,
    LONG = 4,
    FLOAT = 5,
    DOUBLE = 6,
    BYTE_ARRAY = 7,
    STRING = 8,
    LIST = 9,
    COMPOUND = 10,
    INT_ARRAY = 11,
    LONG_ARRAY = 12
}

local END_MT = {TAG=0,__tostring=function() return "TAG_END" end}
local nbt_end = {}
setmetatable(nbt_end,END_MT)
metatables[END_MT] = true
function lib.END()
    return nbt_end
end
    

function lib.isNBT(nbt)
    return getmetatable(nbt) and metatables[getmetatable(nbt)]
end

function lib.getTag(nbt)
    return lib.isNBT(nbt) and getmetatable(nbt).TAG
end

function lib.isNBTNumber(nbt)
    return nbt ~= nbt_end and (lib.getTag(nbt) or tags.BYTE_ARRAY) < tags.BYTE_ARRAY
end
lib.tags = tags

local default_types = {
    function() return lib.BYTE(false) end,
    function() return lib.SHORT(0) end,
    function() return lib.INT(0) end,
    function() return lib.LONG(0) end,
    function() return lib.FLOAT(0) end,
    function() return lib.DOUBLE(0) end,
    function() return lib.BYTE_ARRAY() end,
    function() return lib.STRING("") end,
    function() return lib.LIST(0) end,
    function() return lib.COMPOUND() end,
    function() return lib.INT_ARRAY() end,
    function() return lib.LONG_ARRAY() end
}
default_types[0] = lib.END
local function getDefaultValue(nbt_type)
    expect(1,nbt_type,"number")
    func = default_types[nbt_type]
    return func and func() or error(nbt_type.." is not a valid nbt type")
end

local function cast(tag_type,value)
    nosleep()
    expect(1,tag_type,"number","nil")
    expect(2,value,"number","boolean","string","table")
    if not tag_type then
        if lib.isNBT(value) then return value end
        if type(value) == "number" and math.floor(value) == value then return lib.INT(value)
        elseif type(value) == "number" and math.floor(value) ~= value then return lib.DOUBLE(value)
        elseif type(value) == "string" then return lib.STRING(value)
        elseif type(value) == "boolean" then return lib.BYTE(value)
        elseif type(value) == "table" and tostring(textutils.serialiseJSON(value)):match("^%[.*%]$") then return cast(9,value) --cast to LIST
        elseif textutils.serialiseJSON(value) then return cast(10,value) --cast to COMPOUND
        else return nil,"Could not find an implicit type for the value" end
    end
    assert(default_types[tag_type],"Invalid tag type")
    if tag_type == tags.BYTE then
        return (lib.tonumber(value) or type(value) == "boolean") and lib.BYTE(lib.tonumber(value) or value) or nil,"BYTE can only be cast from a number or boolean value, got "..tostring(value)
    elseif tag_type == tags.SHORT then
        return lib.tonumber(value) and lib.SHORT(lib.tonumber(value)) or nil,"SHORT can only be cast from a number value, got "..tostring(value)
    elseif tag_type == tags.INT then
        return lib.tonumber(value) and lib.INT(lib.tonumber(value)) or nil,"INT can only be cast from a number value, got "..tostring(value)
    elseif tag_type == tags.LONG then
        return lib.tonumber(value) and lib.LONG(lib.tonumber(value)) or nil,"LONG can only be cast from a number value, got "..tostring(value)
    elseif tag_type == tags.FLOAT then
        return lib.tonumber(value) and lib.FLOAT(lib.tonumber(value)) or nil,"FLOAT can only be cast from a number value, got "..tostring(value)
    elseif tag_type == tags.DOUBLE then
        return lib.tonumber(value) and lib.DOUBLE(lib.tonumber(value)) or nil,"DOUBLE can only be cast from a number value, got "..tostring(value)
    elseif tag_type == tags.BYTE_ARRAY then
        if type(value) ~= "table" then return nil,"BYTE ARRAY must be cast from a table value, got "..tostring(value) end
        local byte_array = lib.BYTE_ARRAY()
        for k,v in pairs(value) do
            if type(k) ~= "number" then return nil,"BYTE_ARRAY must only have number keys, got "..tostring(value) end
            s,err = pcall(function() byte_array[k] = v end)
            if not s then return nil,err end
        end
        return byte_array
    elseif tag_type == tags.STRING then
        return type(value) == "string" and lib.STRING(value) or nil,"STRING can only be cast from a string value, got "..tostring(value)
    elseif tag_type == tags.LIST then
        if type(value) ~= "table" then return nil,"LIST must be cast from a table value, got "..tostring(value) end
        local list
        for k,v in pairs(value) do
            if type(k) ~= "number" then return nil,"LIST must only have number keys, got "..tostring(value) end
            if not list then
                local nbt,err = cast(nil,v)
                if nbt then list = lib.LIST(lib.getTag(nbt))
                else return nil,err end
            end
            s,err = pcall(function() list[k] = v end)
            if not s then return nil,err end
        end
        return list or lib.LIST(tags.END) --return end tag list
    elseif tag_type == tags.COMPOUND then
        if type(value) ~= "table" then return nil,"COMPOUND must be cast from a table value, got "..tostring(value) end
        local compound = lib.COMPOUND()
        for k,v in pairs(value) do
            if type(k) ~= "string" then return nil,"COMPOUND must only have string keys, got "..tostring(value) end
            s,err = pcall(function() compound[k] = v end)
            if not s then return nil,err end
        end
        return compound
    elseif tag_type == tags.INT_ARRAY then
        if type(value) ~= "table" then return nil,"INT ARRAY must be cast from a table value, got "..tostring(value) end
        local int_array = lib.INT_ARRAY()
        for k,v in pairs(value) do
            if type(k) ~= "number" then return nil,"INT ARRAY must only have number keys" end
            s,err = pcall(function() int_array[k] = v end)
            if not s then return nil,err end
        end
        return int_array
    elseif tag_type == tags.LONG_ARRAY then
        if type(value) ~= "table" then return nil,"LONG ARRAY must be cast from a table value, got "..tostring(value) end
        local long_array = lib.LONG_ARRAY()
        for k,v in pairs(value) do
            if type(k) ~= "number" then return nil,"LONG ARRAY must only have number keys" end
            s,err = pcall(function() long_array[k] = v end)
            if not s then return nil,err end
        end
        return long_array
    else
        return nil,"Invalid tag_type"
    end
end

local spack,sunpack = string.pack,string.unpack

local function clamp(nValue,nMin,nMax,bInteger)
    expect(1,nValue,"number")
    expect(2,nMin,"number")
    expect(3,nMax,"number")
    expect(4,bInteger,"boolean","nil")
    v = math.min(math.max(nValue,nMin),nMax)
    if bInteger then return math.floor(v) else return v end
end

--Generic metatable for number functions
local NBT_NUMBER = {
    __tonumber = function(self) return self.value end,
    __unm = function(self) return -self.value end,
}

function NBT_NUMBER.__add(a,b)
    if lib.isNBTNumber(a) then a = a.value end
    if lib.isNBTNumber(b) then b = b.value end
    return a+b
end
function NBT_NUMBER.__sub(a,b)
    if lib.isNBTNumber(a) then a = a.value end
    if lib.isNBTNumber(b) then b = b.value end
    return a-b
end
function NBT_NUMBER.__mul(a,b)
    if lib.isNBTNumber(a) then a = a.value end
    if lib.isNBTNumber(b) then b = b.value end
    return a*b
end
function NBT_NUMBER.__div(a,b)
    if lib.isNBTNumber(a) then a = a.value end
    if lib.isNBTNumber(b) then b = b.value end
    return a/b
end
function NBT_NUMBER.__mod(a,b)
    if lib.isNBTNumber(a) then a = a.value end
    if lib.isNBTNumber(b) then b = b.value end
    return a%b
end
function NBT_NUMBER.__pow(a,b)
    if lib.isNBTNumber(a) then a = a.value end
    if lib.isNBTNumber(b) then b = b.value end
    return a^b
end
function NBT_NUMBER.__eq(a,b)
    if lib.isNBTNumber(a) then a = a.value end
    if lib.isNBTNumber(b) then b = b.value end
    return a==b
end
function NBT_NUMBER.__lt(a,b)
    if lib.isNBTNumber(a) then a = a.value end
    if lib.isNBTNumber(b) then b = b.value end
    return a<b
end
function NBT_NUMBER.__le(a,b)
    if lib.isNBTNumber(a) then a = a.value end
    if lib.isNBTNumber(b) then b = b.value end
    return a<=b
end
--Specific metatables for each number
local BYTE_MT = {__index = NBT_NUMBER,TAG=1}
local SHORT_MT = {__index = NBT_NUMBER,TAG=2}
local INT_MT = {__index = NBT_NUMBER,TAG=3}
local LONG_MT = {__index = NBT_NUMBER,TAG=4}
local FLOAT_MT = {__index = NBT_NUMBER,TAG=5}
local DOUBLE_MT = {__index = NBT_NUMBER,TAG=6}
metatables[BYTE_MT] = true
metatables[SHORT_MT] = true
metatables[INT_MT] = true
metatables[FLOAT_MT] = true
metatables[DOUBLE_MT] = true
--why
for k,v in pairs(NBT_NUMBER) do
    BYTE_MT[k],SHORT_MT[k],INT_MT[k],LONG_MT[k],FLOAT_MT[k],DOUBLE_MT[k] = v,v,v,v,v,v
end
--Signed byte (and boolean)
function lib.BYTE(value)
    expect(1,value,"number","boolean")
    local byte = {value=0}
    if value == true then
        byte.value = 1
    elseif value == false then
        byte.value = 0
    else
        byte.value = clamp(value,-128,127,true)
    end
    setmetatable(byte,BYTE_MT)
    return byte
end
function BYTE_MT.__tostring(byte)
    return tostring(byte.value).."b"
end
function BYTE_MT.__tobinary(byte)
    return spack(">b",byte.value)
end
--Signed short
function lib.SHORT(value)
    expect(1,value,"number")
    local short = {value=clamp(value,-32768,32767,true)}
    setmetatable(short,SHORT_MT)
    return short
end
function SHORT_MT.__tostring(short)
    return tostring(short.value).."s"
end
function SHORT_MT.__tobinary(short)
    return spack(">h",short.value)
end
--Signed int
function lib.INT(value)
    expect(1,value,"number")
    local int = {value=clamp(value,-2147483648,2147483647,true)}
    setmetatable(int,INT_MT)
    return int
end
function INT_MT.__tostring(int)
    return tostring(int.value)
end
function INT_MT.__tobinary(int)
    return spack(">i4",int.value)
end
--Signed long (may be problematic due to lua precision issues)
function lib.LONG(value)
    expect(1,value,"number")
    local long = {value=clamp(value,-2^63,2^63-1,true)}
    setmetatable(long,LONG_MT)
    return long
end
function LONG_MT.__tostring(long)
    return tostring(long.value).."l"
end
function LONG_MT.__tobinary(long)
    return spack(">l",long.value)
end
--Signed 4 byte floating point
function lib.FLOAT(value)
    expect(1,value,"number")
    local float = {value=value}
    setmetatable(float,FLOAT_MT)
    return float
end
function FLOAT_MT.__tostring(float)
    local str = tostring(float.value)
    return (str.find("%.") and str or (str .. ".0")) .."f"
end
function FLOAT_MT.__tobinary(float)
    return spack(">f",float.value)
end
--Signed 8 byte double floating point
function lib.DOUBLE(value)
    expect(1,value,"number")
    local double = {value=value}
    setmetatable(double,DOUBLE_MT)
    return double
end
function DOUBLE_MT.__tostring(double)
    local str = tostring(double.value)
    return (str.find("%.") and str or (str .. ".0"))
end
function DOUBLE_MT.__tobinary(double)
    return spack(">d",double.value)
end 

--String stuff
local STRING_MT = {
    __len = function(self) return #self.data end,
    __tostring = function(self) return string.format("%q",self.data) end,
    TAG = 8
}
metatables[STRING_MT] = true
function STRING_MT.__concat(a,b)
    if getmetatable(a) == STRING_MT then a = a.data end
    if getmetatable(b) == STRING_MT then b = b.data end
    return a .. b
end
function STRING_MT.__eq(a,b)
    if getmetatable(a) == STRING_MT then a = a.data end
    if getmetatable(b) == STRING_MT then b = b.data end
    return a == b
end
function STRING_MT.__lt(a,b)
    if getmetatable(a) == STRING_MT then a = a.data end
    if getmetatable(b) == STRING_MT then b = b.data end
    return a < b
end
function STRING_MT.__le(a,b)
    if getmetatable(a) == STRING_MT then a = a.data end
    if getmetatable(b) == STRING_MT then b = b.data end
    return a <= b
end
function lib.STRING(str)
    expect(1,str,"string")
    local s = {data=str}
    setmetatable(s,STRING_MT)
    return s
end
function STRING_MT.__tobinary(str)
    return spack(">H",#str)..str.data
end

--Generic list metatable
local NBT_LIST = {
    __len = function(self) return #rawget(self,"data") end,
    __index = function(self,key) return rawget(self,"data")[key] end,
    __pairs = function(self) return pairs(rawget(self,"data")) end,
    __ipairs = function(self) return ipairs(rawget(self,"data")) end,
    __newindex = function(self,key,value)
        if type(value) ~= "table" or lib.getTag(value) ~= rawget(self,"TYPE") then
            value = assert(cast(rawget(self,"TYPE"),value))
            --error(tostring(value).." is not the same type as the tag in this list")
        end
        if type(key) ~= "number" or math.floor(key) ~= key or key <= 0 then
            error(tostring(key) .. " is not a valid integer index")
        end
        local data = rawget(self,"data")
        local nbt_type = rawget(self,"TYPE")
        for i=#data+1,key-1 do
            data[i] = getDefaultValue(nbt_type)
        end
        data[key]=value
    end,
}
--Specific metatables for each list
local COMPOUND_MT = {TAG=10}
local LIST_MT = {TAG=9}
local BYTE_ARRAY_MT = {TAG=7}
local INT_ARRAY_MT = {TAG=11}
local LONG_ARRAY_MT = {TAG=12}
metatables[COMPOUND_MT] = true
metatables[LIST_MT] = true
metatables[BYTE_ARRAY_MT] = true
metatables[INT_ARRAY_MT] = true
metatables[LONG_ARRAY_MT] = true
--copy over functions
for k,v in pairs(NBT_LIST) do
    COMPOUND_MT[k],LIST_MT[k],BYTE_ARRAY_MT[k],INT_ARRAY_MT[k],LONG_ARRAY_MT[k] = v,v,v,v,v
end

function lib.LIST(tag_type,data)
    expect(1,tag_type,"number")
    expect(2,data,"table","nil")
    assert(default_types[tag_type] or tag_type == -1,"Not a valid list type!")
    local list = {TYPE=tag_type,data={}}
    setmetatable(list,LIST_MT)
    if data then
        for k,v in pairs(data) do
            pcall(function() list[k] = v end)
        end
    end
    return list
end
function LIST_MT.__tostring(list)
    local str = "["
    for k,v in ipairs(list) do
        str = str .. tostring(v) .. ","
    end
    return str:gsub(",$","").."]"
end
function LIST_MT.__tobinary(list,recur)
    nosleep()
    recur = (tonumber(recur) or 0)+1
    if recur >= 512 then error("NBT cannot be nested more than 512 times") end
    local str = string.char(rawget(list,"TYPE"))..spack(">i4",#list)
    for k,v in ipairs(list) do
        str = str .. getmetatable(v).__tobinary(v)
    end
    return str
end
function lib.BYTE_ARRAY(data)
    expect(1,data,"table","nil")
    local byte_array = {TYPE=1,data={}}
    setmetatable(byte_array,BYTE_ARRAY_MT)
    if data then
        for k,v in pairs(data) do
            pcall(function() byte_array[k] = v end)
        end
    end
    return byte_array
end
function BYTE_ARRAY_MT.__tostring(byte_array)
    local str = "[B;"
    for k,v in ipairs(byte_array) do
        str = str .. tostring(v) .. ","
    end
    return str:gsub(",$","").."]"
end
function BYTE_ARRAY_MT.__tobinary(byte_array)
    local str = spack(">i4",#byte_array)
    for k,v in ipairs(byte_array) do
        str = str .. getmetatable(v).__tobinary(v)
    end
    return str
end
function lib.INT_ARRAY(data)
    expect(1,data,"table","nil")
    local int_array = {TYPE=3,data={}}
    setmetatable(int_array,INT_ARRAY_MT)
    if data then
        for k,v in pairs(data) do
            pcall(function() int_array[k] = v end)
        end
    end
    return int_array
end
function INT_ARRAY_MT.__tostring(int_array)
    local str = "[I;"
    for k,v in ipairs(int_array) do
        str = str .. tostring(v) .. ","
    end
    return str:gsub(",$","").."]"
end
function INT_ARRAY_MT.__tobinary(int_array)
    local str = spack(">i4",#int_array)
    for k,v in ipairs(int_array) do
        str = str .. getmetatable(v).__tobinary(v)
    end
    return str
end
function lib.LONG_ARRAY()
    local long_array = {TYPE=4,data={}}
    setmetatable(long_array,LONG_ARRAY_MT)
    if data then
        for k,v in pairs(data) do
            pcall(function() long_array[k] = v end)
        end
    end
    return long_array
end
function LONG_ARRAY_MT.__tostring(long_array)
    local str = "[L;"
    for k,v in ipairs(long_array) do
        str = str .. tostring(v) .. ","
    end
    return str:gsub(",$","").."]"
end
function LONG_ARRAY_MT.__tobinary(long_array)
    local str = spack(">i4",#long_array)
    for k,v in ipairs(long_array) do
        str = str .. getmetatable(v).__tobinary(v)
    end
    return str
end

function lib.COMPOUND(data)
    expect(1,data,"table","nil")
    local compound = {data={}}
    setmetatable(compound,COMPOUND_MT)
    if data then
        for k,v in pairs(data) do
            pcall(function() compound[k] = v end)
        end
    end
    return compound
end
function COMPOUND_MT.__tostring(compound)
    local str = "{"
    for k,v in pairs(compound) do
        str = str .. string.format("%q",k)..":"..tostring(v)..","
    end
    return str:gsub(",$","").."}"
end
function COMPOUND_MT.__newindex(self,key,value)
    if not default_types[lib.getTag(value) or -1] then
        value = assert(cast(nil,value))
        --error(tostring(value).." is not a nbt component!")
    end
    if getmetatable(key) == STRING_MT then key = key.data end
    if type(key) ~= "string" then
        error(tostring(key) .. " is not a string index",2)
    end
    rawget(self,"data")[key]=value
end
--I hate lua tables
function COMPOUND_MT.__len(self)
    local count = 0
    for k,v in pairs(rawget(self,"data")) do
        count = count + 1
    end
    return count
end
function COMPOUND_MT.__tobinary(compound,recur)
    nosleep()
    recur = (tonumber(recur) or 0)+1
    if recur >= 512 then error("NBT cannot be nested more than 512 times",2) end
    local str = ""
    for k,v in pairs(compound) do
        str = str .. string.char(lib.getTag(v))..spack(">H",#k)..k..getmetatable(v).__tobinary(v,recur)
    end
    return str..string.char(0)
end

function lib.tobinary(nbt)
    expect(1,nbt,"table")
    local mt = getmetatable(nbt)
    assert(mt == COMPOUND_MT,"Can only convert compound tags to binary")
    return mt.__tobinary(nbt)
end
local function buffer(str)
    local str,idx = str,1
    return function(count)
        if idx > #str then return "\000" end --nil end
        count = tonumber(count) or 1
        local s = str:sub(idx,idx+count-1)
        idx = idx + count
        return s
    end
end
local function fromBinaryRaw(buf,t)
    nosleep()
    if t == 1 then
        return lib.BYTE(sunpack(">b",buf()))
    elseif t == 2 then
        return lib.SHORT(sunpack(">h",buf(2)))
    elseif t == 3 then
        return lib.INT(sunpack(">i4",buf(4)))
    elseif t == 4 then
        return lib.LONG(sunpack(">l",buf(8)))
    elseif t == 5 then
        return lib.FLOAT(sunpack(">f",buf(4)))
    elseif t == 6 then
        return lib.DOUBLE(sunpack(">d",buf(8)))
    elseif t == 8 then
        local len = sunpack(">H",buf(2))
        return lib.STRING(buf(len))
    elseif t == 7 then
        local len = sunpack(">i4",buf(4))
        local b = lib.BYTE_ARRAY()
        for i=1,len do
            b[i] = sunpack(">b",buf())
        end
        return b
    elseif t == 9 then
        local id = buf():byte()
        local l = lib.LIST(id)
        local len = sunpack(">i4",buf(4))
        for i=1,len do
            l[i] = fromBinaryRaw(buf,id)
        end
        return l
    elseif t == 10 then
        local id = buf():byte()
        local c = lib.COMPOUND()
        while id and id ~= 0 do
            local len = sunpack(">H",buf(2))
            local key = buf(len)
            c[key] = fromBinaryRaw(buf,id)
            id = buf():byte()
        end
        return c
    elseif t == 11 then
        local len = sunpack(">i4",buf(4))
        local b = lib.INT_ARRAY()
        for i=1,len do
            b[i] = sunpack(">i4",buf(4))
        end
        return b
    elseif t == 12 then
        local len = sunpack(">i4",buf(4))
        local b = lib.LONG_ARRAY()
        for i=1,len do
            b[i] = sunpack(">l",buf(8))
        end
        return b
    else
        error("invalid tag "..tostring(t))
    end
end
function lib.frombinary(str)
    expect(1,str,"string")
    return fromBinaryRaw(buffer(str),10)
end

local function parseErr(str,pos,err)
    error(err .. ' ("'..str:sub(pos-10,pos)..'"<-- here)',pos)
end

local function aParseErr(value,...)
    if value then return value,... else return parseErr(...) end
end

local parse = {}

function parse.number(str,pos)
    local sPos,ePos = str:find("%-?%d+%.?%d*",pos)
    aParseErr(sPos,str,pos,"Could not serialise number")
    local value = aParseErr(tonumber(str:sub(sPos,ePos)),str,ePos,"Could not serialise number")
    local nextC = str:sub(ePos+1,ePos+1):lower()
    if str:sub(sPos,ePos):find("%.") then --floats or doubles
        if nextC == "f" then return lib.FLOAT(value),ePos+2,5
        elseif not nextC:match("%a") then return lib.DOUBLE(value),ePos+1,6
        else parseErr(str,ePos+1,"Number has a decimal, but isn't a float or double value") end
    else
        if nextC == "b" then return lib.BYTE(value),ePos+2,1
        elseif nextC == "s" then return lib.SHORT(value),ePos+2,2
        elseif nextC == "l" then return lib.LONG(value),ePos+2,4
        elseif not nextC:match("%a") then return lib.INT(value),ePos+1,3
        else parseErr(str,ePos+1,"Number has invalid character after it") end
    end
    parseError(str,pos,"Unknown error parsing number")
end

function parse.list(str,pos,obj)
    local tag_type = rawget(obj,"TYPE")
    local c,o,t = ""
    while true do
        pos = aParseErr(str:find("%S",pos),str,pos,"Missing `]` bracket to close list or array")
        c = str:sub(pos,pos)
        if c == "]" then 
            if tag_type == -1 then rawset(obj,"TYPE",0) end
            return obj,pos+1,lib.getTag(obj)
        else
            o,pos,t = parse.main(str,pos)
            if t == tag_type then
                obj[#obj+1] = o
                pos = aParseErr(str:find("%S",pos),str,pos,"Missing `]` bracket to close list or array")
                c = str:sub(pos,pos)
                if c == ']' then return obj,pos+1,lib.getTag(obj)
                elseif c ~= "," then
                    parseErr(str,pos,"Could not parse list or array, expected `,` to seperate entries")
                end
                pos = pos + 1
            elseif tag_type == -1 then --Make lists type the type of their first object
                rawset(obj,"TYPE",t)
                tag_type = t
                obj[#obj+1] = o
                pos = aParseErr(str:find("%S",pos),str,pos,"Missing `]` bracket to close list or array")
                c = str:sub(pos,pos)
                if c == ']' then return obj,pos+1,lib.getTag(obj)
                elseif c ~= "," then
                    parseErr(str,pos,"Could not parse list or array, expected `,` to seperate entries")
                end
                pos = pos + 1
            else
                parseErr(str,pos,"Invalid entry type, list is of type "..tag_type..", but object is "..t)
            end
        end
    end
end 



function parse.string(str,pos)
    local sType = str:sub(pos,pos)
    if sType == '"' or sType == "'" then
        local endPos = aParseErr(str:find("[^\\]"..sType,pos),str,pos,"Missing quotes to terminate the string")
        return lib.STRING(textutils.unserialise(str:sub(pos,endPos+1))),endPos+2,8
    else
        local endPos = aParseErr(str:find("[^%w_]",pos),str,pos,"Invalid character in key")
        return lib.STRING(str:sub(pos,endPos-1)),endPos,8
    end
    parseErr(str,pos,"Unknown error parsing string")
end

function parse.compound(str,pos)
    nosleep()
    local c,compound,key = "",lib.COMPOUND()
    while true do
        pos = aParseErr(str:find("%S",pos),str,pos,"Missing `}` bracket to close compound tag")
        c = str:sub(pos,pos)
        if c == "}" then return compound,pos+1,10
        elseif c:match("[%a'\"]") then
            key,pos = parse.string(str,pos)
            pos = aParseErr(str:find("%S",pos),str,pos,"Missing `}` bracket to close compound tag")
            c = str:sub(pos,pos)
            if c ~= ":" then
                parseErr(str,pos,"Could not parse compound tag, expected : to seperate key and value")
            end
            compound[key],pos = parse.main(str,pos+1)
            pos = aParseErr(str:find("%S",pos),str,pos,"Missing `}` bracket to close compound tag")
            c = str:sub(pos,pos)
            if c == "}" then return compound,pos+1,10
            elseif c ~= "," then
                parseErr(str,pos,"Could not parse compound tag, expected `,` to seperate entries")
            end
            pos = pos + 1
        elseif c == "" then
            parseErr(str,pos,"Missing `}` bracket to close compound tag")
        else
            parseErr(str,pos,"Invalid character for compound tag")
        end
    end
end



function parse.main(str,pos)
    nosleep()
    pos = aParseErr(str:find("%S",pos),str,pos,"NBT string ended too early")
    local c = str:sub(pos,pos)
    if c == "{" then
        pos = str:find("%S",pos+1) --skip next whitespace
        return parse.compound(str,pos)
    elseif c == '"' or c == "'" then
        return parse.string(str,pos)
    elseif c:match("[%-%d]") then
        return parse.number(str,pos)
    elseif c == "[" then
        local t = str:sub(pos+1,pos+2)
        if t == "I;" then
            return parse.list(str,pos+3,lib.INT_ARRAY())
        elseif t == "B;" then
            return parse.list(str,pos+3,lib.BYTE_ARRAY())
        elseif t == "L;" then
            return parse.list(str,pos+3,lib.LONG_ARRAY())
        else
            return parse.list(str,pos+1,lib.LIST(-1))
        end
    elseif c == "t" and str:sub(pos,pos+3) == "true" then
        return lib.BYTE(true),pos+4,1
    elseif c == "f" and str:sub(pos,pos+4) == "false" then
        return lib.BYTE(false),pos+5,1
    else
        parseErr(str,pos,"Invalid character")
    end
end

function lib.fromstring(str)
    return ({parse.main(str,1)})[1]
end

local str_overrides = {
    ["\n"] = '\\n',
    ["\t"] = '\\t',
    [string.char(0)] = "\\000",
    ['\r'] = '\\r',
    ['\a'] = '\\a',
    ['\b'] = '\\b',
    ['\f'] = '\\f'
}

function lib.serialize(nbt,sTab,bExpandArrays,sCurrentTab)
    local tag = assert(type(nbt) == "table" and lib.getTag(nbt),"Bad argument #1 (nbt expected, got "..type(nbt)..")")
    expect(2,sTab,"string","nil")
    expect(3,bExpandArrays,"boolean","nil")
    expect(4,sCurrentTab,"string","nil")
    sTab = type(sTab) == "string" and sTab or " "
    sCurrentTab = sCurrentTab or ""
    if tag <= 6 then
        return tostring(nbt)
    elseif tag == 8 then
        return tostring(nbt):gsub("[\000-\x20]",function(str) return str_overrides[str] or str end)
    elseif tag == 10 then
        if #nbt == 0 then return "{}" end
        local str = "{"
        for k,v in pairs(nbt) do
            str = str .. string.format("\n"..sCurrentTab..sTab.."%q:%s,",k,lib.serialize(v,sTab,bExpandArrays,sCurrentTab..sTab))
        end
        return str:gsub(',$','') .. "\n" .. sCurrentTab .. "}"
    elseif tag == 9 then
        local tag_type = rawget(nbt,"TYPE")
        if #nbt == 0 then return "[]" end
        if not bExpandArrays and (tag_type <= 6 or tag_type == 8) then return tostring(nbt) end
        local str = "["
        for k,v in ipairs(nbt) do
            str = str .. string.format("\n"..sCurrentTab..sTab.."%s,",lib.serialize(v,sTab,bExpandArrays,sCurrentTab..sTab))
        end
        return str:gsub(',$','') .. "\n" .. sCurrentTab .. "]"  
    elseif bExpandArrays then
        local str = "["
        if tag_type == 7 then
            str = str .. "B;"
        elseif tag_type == 11 then
            str = str .. "I;"
        elseif tag_type == 12 then
            str = str .. "L;"
        end
        if #nbt == 0 then return str .. "]" end
        for k,v in ipairs(nbt) do
            str = str .. string.format("\n"..sCurrentTab..sTab.."%s,",tostring(v))
        end
        return str:gsub(',$','') .. "\n" .. sCurrentTab .. "]"
    else
        return tostring(nbt)
    end
end
lib.serialise = serialize

function lib.tonumber(value)
    return tonumber(value) or (type(value) == "table" and getmetatable(value) and (getmetatable(value).__tonumber or function()end)(value))
end
    
lib.cast = cast
return lib