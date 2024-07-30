local nbt = require"nbt"
local zip = require"LibDeflate"
local expect = require("cc.expect").expect

--true if palette blocks are the same
local function isPaletteEqual(pb1,pb2)
    --print("check palette equal")
    if tostring(pb1.Name) ~= tostring(pb2.Name) then return false end
    if pb1.Properties then
        if not pb2.Properties then return false end
        for k,v in pairs(pb1.Properties) do
            if tostring(v) ~= tostring(pb2.Properties[k]) then return false end
        end
        for k,v in pairs(pb2.Properties) do
            if tostring(v) ~= tostring(pb1.Properties[k]) then return false end
        end
    else
        return pb1.Properties == pb2.Properties
    end
end

--Merge the other schematic into the main one
local function mergeSchematic(main_schem_root,other_schem,other_schem_pos,main_schem_pos)
    --print("merge schematic")
    --_,other_schem = next(rawget(other_schem,"data")) --schematics are wrapped in a secondary compound tag for no good reason
    local remap = mergePalettes(main_schem_root.palette,other_schem.palette)
    --copy over the blocks with the remap
    for _,block in pairs(other_schem.blocks) do
        --print("merging blocks")
        --write("blockstate: "..tostring(block.state))
        block.state = remap[nbt.tonumber(block.state)]
        --print(" remap: "..tostring(block.state))
        for i=1,3 do
            block.pos[i] = other_schem_pos[i]+block.pos[i]-main_schem_pos[i]
            --main_schem.root.size[i] = math.max(main_schem.root.size[i],block.pos[i]+1) --update schem size
        end
        main_schem_root.blocks[#main_schem_root.blocks+1] = block
    end
    for i=1,3 do
        main_schem_root.size[i] = math.max(nbt.tonumber(main_schem_root.size[i]),other_schem_pos[i]+other_schem.size[i]-main_schem_pos[i])
        main_schem_pos[i] = math.min(nbt.tonumber(main_schem_pos[i]),nbt.tonumber(other_schem_pos[i]))
    end
end

local function mergePalettes(p1,p2)
    --print("mergine palettes")
    local remap = {}
    for oldIdx,pb2 in pairs(p2) do
        oldIdx = oldIdx - 1 --I hate 1s based indexing
        for idx,pb1 in pairs(p1) do
            if isPaletteEqual(pb1,pb2) then
                remap[oldIdx] = idx - 1
                break
            end
        end
        if not remap[oldIdx] then
            remap[oldIdx] = #p1 --do this first because it is intentionally 1 smaller than the lua index (nbt uses 0 based indexing)
            p1[#p1+1] = pb2
        end
    end
    return remap
end

local osepoch = os.epoch
local nosleeptimer = osepoch("UTC") + 5000
local function nosleep()
    if osepoch("UTC") > nosleeptimer then
        os.queueEvent("nosleep")
        os.pullEvent()
        nosleeptimer = osepoch("UTC") + 5000
    end
end

local SCHEM = {}
local schem_mt = {__index=SCHEM}
function SCHEM.new()
    local data = {}
    local schem = nbt.COMPOUND()
    schem.root = nbt.COMPOUND()
    schem.root.blocks = nbt.LIST(10)
    schem.root.size = nbt.LIST(3,{0,0,0})
    schem.root.pos = nbt.LIST(3,{0,0,0})
    -- for i=1,3 do
    --     schem.root.size[i] = 0
    --     schem.root.pos[i] = 0
    -- end
    schem.root.palette = nbt.LIST(10)
    print(schem.root.palette)
    schem.root.DataVersion = 2975
    data.schem = schem
    data.palette_cache = {}
    data.pos_cache = {}
    setmetatable(data,schem_mt)
    return data
end
function SCHEM.merge(schem1,schem2)
    if getmetatable(schem1) ~= schem_mt or getmetatable(schem2) ~= schem_mt then error("Arguments must both be schematics") end
    return mergeSchematic(schem1.schem.root,schem2.schem.root,schem2.schem.root.pos,schem2.schem.root.pos)
end
function SCHEM.open(path)
    assert(fs.exists(path),"Schematic must be part of a file")
    local f = fs.open(path,"r")
    local data = f.readAll()
    f.close()
    nosleep()
    local unzipped_data = assert(zip:DecompressGzip(data))
    local schem = assert(nbt.frombinary(unzipped_data))
    local data = {schem=schem,palette_cache = {},pos_cache = {}}
    nosleep()
    for k,v in pairs(schem.root.blocks) do
        nosleep()
        data.pos_cache[tostring(v.pos)] = k
    end
    for k,v in pairs(schem.root.palette) do
        if not v.Properties then
            data.palette_cache[v.Name.data] = k - 1 --0 based indexing for the State property
        end
    end
    nosleep()
    setmetatable(data,schem_mt)
    return data
end
function SCHEM.setBlock(schem,x,y,z,name,properties,tag)
    if getmetatable(schem) ~= schem_mt then error("Bad argument #1 (schem expected, got "..type(schem)..")") end
    expect(2,x,"number")
    expect(3,y,"number")
    expect(4,z,"number")
    expect(5,name,"string")
    expect(6,properties,"table","nil")
    expect(7,nbt,"table","nil")
    local state = #schem.schem.root.palette
    if not properties then
        if schem.palette_cache[name] then
            state = schem.palette_cache[name]
        else
            schem.palette_cache[name] = state
            print(schem.schem.root.palette)
            schem.schem.root.palette[state+1] = nbt.COMPOUND({Name=name}) 
        end
    else
        schem.schem.root.palette[state+1] = nbt.COMPOUND({Name=name,Properties=properties})
    end
    local pos = string.format("[%d,%d,%d]",x,y,z)
    local blockIdx
    if schem.pos_cache[pos] then
        blockIdx = schem.pos_cache[pos]
    else
        blockIdx = #schem.schem.root.blocks+1
        schem.pos_cache[pos] = blockIdx
    end
    local block = nbt.COMPOUND({state=state,pos=nbt.LIST(3,{x,y,z})})
    if tag then
        block.nbt = tag
    end
    schem.schem.root.blocks[blockIdx] = block
    return schem
end
function SCHEM.save(schem,path)
    if getmetatable(schem) ~= schem_mt then error("Bad argument #1 (schem expected, got "..type(schem)..")") end
    expect(2,path,"string")
    os.queueEvent("nosleep")
    os.pullEvent()
    local binarydata = assert(nbt.tobinary(schem.schem))
    os.queueEvent("nosleep")
    os.pullEvent()
    local zippeddata = assert(zip:CompressGzip(binarydata))
    os.queueEvent("nosleep")
    os.pullEvent()
    local f = fs.open(path,"w+")
    f.write(zippeddata)
    f.close()
    return schem
end
function SCHEM.setSize(schem,x,y,z)
    if getmetatable(schem) ~= schem_mt then error("Bad argument #1 (schem expected, got "..type(schem)..")") end
    expect(2,x,"number")
    expect(3,y,"number")
    expect(4,z,"number")
    schem.schem.root.size = nbt.LIST(3,{x,y,z})
    return schem
end
local SCHEM_MT = {
    __call = SCHEM.new
}
setmetatable(SCHEM,SCHEM_MT)

return SCHEM