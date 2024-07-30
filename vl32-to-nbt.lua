local zip = require("LibDeflate")
local atlaslib = require("atlas")
local expect = require("cc.expect").expect
local schem = require("schem")

local args = {...}
local spack,sunpack,sbyte = string.pack,string.unpack,string.byte
local osepoch = os.epoch
local ibe = ">i4"

local input_dir,output_dir,offset = args[1],args[2],tonumber(args[3])
expect(1,input_dir,"string")
expect(2,output_dir,"string")
expect(3,offset,"number","nil")
if not offset or offset < 0 then offset = 0 end
offset = offset*16

if not fs.isDir(input_dir) then error("Bad argument #1 (directory expected, got "..type(input_dir)..")") end
if not fs.isDir(output_dir) then error("Bad argument #1 (directory expected, got "..type(output_dir)..")") end

local VL_CHUNK_SIZE = 4096
local SCHEMATIC_SIZE = 64

local vls = fs.find(fs.combine(input_dir,"*.vl32"))
if #vls == 0 then error("Could not find any .vl32 files in input directory "..input_dir) end

local atlas
local atlas_paths = fs.find(fs.combine(input_dir,"*.atlas"))
if #atlas_paths == 0 or not fs.exists(atlas_paths[1]) then
    print("Please provide an input directory with resource files inside to create the atlas")
    atlas = atlaslib.create(read())
else
    print("loading atlas from path",atlas_paths[1])
    atlas = atlaslib.load(atlas_paths[1])
end
--lower nosleep threshhold
local nosleeptimer = osepoch("UTC") + 5000
local function nosleep()
    if os.epoch("UTC") > nosleeptimer then
        os.queueEvent("nosleep")
        os.pullEvent()
        nosleeptimer = osepoch("UTC") + 5000
    end
end

local iter_count = offset/16
local maxX = term.getSize()

local numVoxels = 0
for k,v in pairs(vls) do
    numVoxels = numVoxels + fs.getSize(v)/16
end
local barLength = maxX - 3

local function printProgressBar()
    local progress = iter_count/numVoxels
    term.write(string.format("%.2d%%",progress*100))
    local bar = string.rep(" ",progress*barLength)..string.rep("\x7f",(1-progress)*barLength)
    term.blit(bar,string.rep("f",#bar),string.rep("9",#bar))
    --term.write(string.format("%.2d%%%s%s",progress,string.rep("\x7f",progress*barLength),string.rep("_",(1-progress)*barLength)))
    print()
end

local startTime = osepoch("UTC")

--wrap in pcall to avoid early stream closing
local function do_vl_chunk(stream)
    local loaded_schems = {}
    local atlas_cache = {}
    print(string.format("%d/%d voxels| Elapsed time:",iter_count,numVoxels),os.date("%T",(osepoch("UTC")-startTime)/1000))
    pcall(printProgressBar)
    local s,err = pcall(function()
            for i=1,VL_CHUNK_SIZE do
                iter_count = iter_count + 1
                nosleep()
                local x,y,z = sunpack(ibe,stream(4)),sunpack(ibe,stream(4)),sunpack(ibe,stream(4))
                local argb = stream(4)
                --local a,r,g,b = stream(),sbyte(stream()),sbyte(stream()),sbyte(stream())
                --local block = atlaslib.getClosestBlock(atlas,r,g,b)
                local block
                if atlas_cache[argb] then
                    block = atlas_cache[argb]
                else
                    block = atlaslib.getClosestBlock(atlas,sbyte(argb,2),sbyte(argb,3),sbyte(argb,4))
                    atlas_cache[argb] = block
                end
                --skip the a part
                local schem_path = string.format("ots_y%d_x%d_z%d.nbt",y/SCHEMATIC_SIZE,x/SCHEMATIC_SIZE,z/SCHEMATIC_SIZE)
                if not loaded_schems[schem_path] then
                    if fs.exists(fs.combine(output_dir,schem_path)) then
                        print("loading existing schem at",schem_path)
                        loaded_schems[schem_path] = schem.open(fs.combine(output_dir,schem_path)):setBlock(x%SCHEMATIC_SIZE,y%SCHEMATIC_SIZE,z%SCHEMATIC_SIZE,block)
                        nosleep()
                    else
                        print("creating new schem for path",schem_path)
                        loaded_schems[schem_path] = schem:new():setSize(SCHEMATIC_SIZE,SCHEMATIC_SIZE,SCHEMATIC_SIZE):setBlock(x%SCHEMATIC_SIZE,y%SCHEMATIC_SIZE,z%SCHEMATIC_SIZE,block)
                        nosleep()
                    end
                else
                    loaded_schems[schem_path]:setBlock(x%SCHEMATIC_SIZE,y%SCHEMATIC_SIZE,z%SCHEMATIC_SIZE,block)
                end
            end
    end)
    print("saving schematics")
    for path,schematic in pairs(loaded_schems) do
        schematic:save(fs.combine(output_dir,path))
        nosleep()
    end
    if not s then 
        printError(err)
        if err:find("yielding") then
            nosleep()
            return true --Ignore yield bullshit
        end
    end
    return s,err
end

for k,path in pairs(vls) do
    print("loading vl32 from",path)
    local file = fs.open(path,"r")
    if offset > 0 then
        offset = offset - #file.read(offset)
    end
    while do_vl_chunk(file.read) do
        nosleep()
    end
    file.close()
end