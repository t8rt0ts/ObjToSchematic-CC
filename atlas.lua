local png = require("png") --https://github.com/9551-Dev/pngLua/blob/master/png.lua
local expect = require("cc.expect").expect

local function packrgba(r,g,b,a)
    return a*0x1000000 + b*0x10000 + g* 0x100 + r
end
local function unpackrgba(rgba)
    local t = {}
    for i=1,4 do
        table.insert(t,rgba%256)
        rgba = math.floor(rgba/256)
    end
    return unpack(t)
end
local function range(argNum,num,min,max)
    assert(type(num) == "number" and num >= min and num <= max,string.format("Bad argument #%d (Expected number between %d and %d, got %s)",argNum,min,max,tostring(num)))
end
--a1 has to be a real alpha, but a2 can be nil (only accept if a1 is 255), or -1 (ignore alpha entirely)
local function compareColors(r1,g1,b1,a1,r2,g2,b2,a2)
    if not a2 then
        if a1 == 255 then
            return compareColors(r1,g1,b1,255,r2,g2,b2,255)
        else
            return math.huge
        end
    end
    local R = (r2+r1)/2
    local sum
    if R >= 128 then
        sum = 3*(r1-r2)^2+4*(g1-g2)^2+2*(b1-b2)^2
    else
        sum = 2*(r1-r2)^2+4*(g1-g2)^2+3*(b1-b2)^2
    end
    if a2 < 0 then return sum
    else
        return sum + 4*(a1-a2)^2
    end
end
    

local function loadImg(baseDir,resourceKey,bVerbose)
    if not resourceKey:find(":") then resourceKey = "minecraft:"..resourceKey end
    local path = fs.find(fs.combine(baseDir,"*/assets",resourceKey:match("^[^:]+"),"textures",resourceKey:match(":(.+)")..".png"))[1]
    print(path)
    if not path or not fs.exists(path) then 
        if bVerbose then print("path does not exist,",path) end
    return end
    return png(path)
end

local function getAverageColor(img)
    local r,g,b,a,cRGB,cA = 0,0,0,0,0,0
    for i=1,img.width do
        for j=1,img.height do
            local p = img:get_pixel(i,j)
            if p then
                local pR,pG,pB,pA = p:unpack()
                a = a+pA
                cA = cA+1
                if pA ~= 0 then
                    cRGB = cRGB + 1
                    r,g,b = r+pR,g+pG,b+pB
                end
            end
        end
    end
    -- for k,v in pairs(img.pixels) do
    --     for j,w in pairs(v) do
    --         --if w.A == 0 then return nil end
    --         a = a+w.A
    --         cA = cA + 1
    --         if w.A ~= 0 then 
    --             cRGB = cRGB + 1
    --             r,g,b = r+w.R,g+w.G,b+w.B
    --         end
    --     end
    -- end
    return math.floor(255.99*r/cRGB),math.floor(255.99*g/cRGB),math.floor(255.99*b/cRGB),math.floor(255.99*a/cA)
end

local function calculateColor(bVerbose,sBaseDir,...)
    local r,g,b,a,cRGB,cA = 0,0,0,0,0,0
    local args = {...}
    for i=1,#args,2 do
        local weight = args[i+1] or 1
        local img = loadImg(sBaseDir,tostring(args[i]),bVerbose)
        if not img then return end
        local nR,nG,nB,nA = getAverageColor(img)
        if not nR then return end
        r,g,b,a = r+weight*nR,g+weight*nG,b+weight*nB,a+weight*nA
        cRGB,cA = cRGB+weight,cA+weight
    end
    return math.floor(r/cRGB),math.floor(g/cRGB),math.floor(b/cRGB),math.floor(a/cA)
end
    
--TODO: fix for the weird uv thing in `https://minecraft.fandom.com/wiki/Tutorials/Models#Examples:_Condensing_multiple_textures_into_one_file`
local function loadModelBasic(sBaseDir,tTextures,tElements,bVerbose)
    local tWeights = {}
    for k,element in pairs(tElements) do
        for _,face in pairs(element.faces) do
            local texture = face.texture:sub(2) --remove the # at the start
            if tTextures[texture] then
                tWeights[texture] = (tWeights[texture] or 0) + 1
            else
                return nil --No defined texture means that its a generic template block
            end
        end
    end
    local packedWeights = {bVerbose,sBaseDir}
    for texture,weight in pairs(tWeights) do
        table.insert(packedWeights,tTextures[texture])
        table.insert(packWeights,weight)
    end
    return calculateColor(unpack(packedWeights))
end

local serializers = {
    ["minecraft:block/cube_all"] = function(bVerbose,sBaseDir,tTextures) return calculateColor(bVerbose,sBaseDir,tTextures.all) end,
    ["minecraft:block/cube"] = function(bVerbose,sBaseDir,tTextures,tElements)
        if tElements then --deal with elements overrides
            return loadModelBasic(sBaseDir,tTextures,tElements,bVerbose)
        end
        return calculateColor(bVerbose,sBaseDir,
            tTextures.down,1,
            tTextures.up,1,
            tTextures.north,1,
            tTextures.south,1,
            tTextures.east,1,
            tTextures.west,1
        ) end,
    ["minecraft:block/cube_bottom_top"] = function(bVerbose,sBaseDir,tTextures,tElements)
        return calculateColor(bVerbose,sBaseDir,
            tTextures.side,4,
            tTextures.bottom,1,
            tTextures.top,1
        ) end,
    ["minecraft:block/cube_column"] = function(bVerbose,sBaseDir,tTextures,tElements)
        return calculateColor(bVerbose,sBaseDir,
            tTextures["end"],2,
            tTextures.side,4
        ) end,
    --specifically skipping cube_column_horizontal because its only for logs (?) and just causes problems
    ["minecraft:template_glazed_terracotta"] = function(bVerbose,sBaseDir,tTextures) return calculateColor(bVerbose,sBaseDir,tTextures.pattern) end
}
for parent,func in pairs(serializers) do
    if parent:match("^minecraft:") then
        serializers[parent:sub(11)] = func --make a copy for implied `minecraft:` 
    end
end

local function loadModelJson(baseDir,path,bVerbose)
    if not fs.exists(path) then return end
    local f = fs.open(path,"r")
    local json = textutils.unserialiseJSON(f.readAll())
    f.close()
    if not json then return end
    if json.parent and serializers[json.parent] then
        return serializers[json.parent](bVerbose,baseDir,json.textures,json.elements)
    end
end

local atlas = {}
function atlas.create(baseDir,bVerbose)
    expect(1,baseDir,"string")
    assert(fs.exists(baseDir),"Must provide a directory with resource files inside")
    local blocks = fs.find(fs.combine(baseDir,"*/assets/*/blockstates/*.json"))
    --local models = fs.find(fs.combine(baseDir,"*/assets/*/models/block/*.json")) --no recursive searching because that messes with namespace
    if #blocks == 0 then error("Could not find blocks in the directory, make sure the blocks are defined in"..fs.combine(baseDir,"<any>/assets/<mod_id>/blockstates/<item_id>.json")) end
    local atlasTable = {}
    local epochCheck = os.epoch("UTC") + 6
    for _,path in pairs(blocks) do
        local modelPath = path:gsub("blockstates","models/block")
        print(modelPath)
        local r,g,b,a = loadModelJson(baseDir,modelPath,bVerbose)
        if os.epoch("UTC") > epochCheck then os.queueEvent("nosleep");os.pullEvent() end
        if r then
            local modid,itemid = modelPath:match("assets/([%w_]+)/models/block/([%w_]+)%.json$")
            if modid then atlasTable[modid..":"..itemid] = {r,g,b,a} end
        end
    end
    setmetatable(atlasTable,atlas)
    return atlasTable
end
function atlas.save(atlasTable,output)
    expect(1,atlasTable,"table")
    expect(2,output,"string")
    assert(getmetatable(atlasTable) == atlas,"Can only save atlases")
    local str = ""
    for block,rgba in pairs(atlasTable) do
        str = str .. block .. "|" .. string.format("%.8x",packrgba(unpack(rgba))) .. "\n"
    end
    str = str:gsub("\n$","")
    local f = fs.open(output,"w+")
    f.write(str)
    f.close()
end

function atlas.load(input)
    expect(1,input,"string")
    if not fs.exists(input) then return false,"path does not exist" end
    local f = fs.open(input,"r")
    local data = f.readAll()
    f.close()
    local atlasTable = {}
    for modid,rgba in data:gmatch("([%w_:]+)|(%x+)") do
        atlasTable[modid] = {unpackrgba(tonumber(rgba,16))}
    end
    setmetatable(atlasTable,atlas)
    return atlasTable
end

function atlas.getClosestBlock(atlasTable,r,g,b,a)
    assert(getmetatable(atlasTable) == atlas,"Bad argument #1 (atlas expected, got "..type(atlasTable))
    range(2,r,0,255);range(3,g,0,255);range(4,b,0,255);
    expect(5,a,"number","nil")
    local bestblock,bestscore = "minecraft:air",math.huge
    for block,rgba in pairs(atlasTable) do
        
        local score = compareColors(rgba[1],rgba[2],rgba[3],rgba[4],r,g,b,a)
        if score == 0 then return block
        elseif score < bestscore then
            bestscore,bestblock = score,block
        end
    end
    return bestblock
end
return atlas 