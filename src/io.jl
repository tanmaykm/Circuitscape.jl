
typealias NoData Union(Nothing,Number)

const FILE_TYPE_NPY                 = 1
const FILE_TYPE_AAGRID              = 2
const FILE_TYPE_TXTLIST             = 3
const FILE_TYPE_INCL_PAIRS_AAGRID   = 4
const FILE_TYPE_INCL_PAIRS          = 5

const FILE_HDR_GZIP                 = [0x1f, 0x8b, 0x08]
const FILE_HDR_NPY                  = [0x93, "NUMPY".data]
const FILE_HDR_AAGRID               = ["ncols".data]
const FILE_HDR_INCL_PAIRS_AAGRID    = ["min".data]
const FILE_HDR_INCL_PAIRS           = ["mode".data]

const iologger = getlogger("circuitscape.io")

MSG_RESAMPLE(raster_name, attrib) = "$raster_name raster has different $attrib than habitat raster. Circuitscape will try to crudely resample the raster. We recommend using the \"Export to Circuitscape\" ArcGIS tool to create ASCII grids with compatible cell size and extent."

MSG_NO_RESAMPLE(raster_name, attrib) = "$raster_name raster must have same $attrib as habitat raster"


#######################################
# UTILITY METHODS
#######################################
_check_file_exists(filename::String) = ((stat(filename).ctime == 0) && error("File $filename does not exist"); true)

function _open_auto_uncompress(filename::String)
    f = open(filename, "r")
    try
        hdr = read(f, Array(Uint8, 3))
        if hdr == FILE_HDR_GZIP
            close(f)
            f = GZip.open(filename, "r")
        end
    catch
        close(f)
        f = nothing
    end
    f
end

function _guess_file_type(filename::String) 
    io = _open_auto_uncompress(filename)
    try
        ret = _guess_file_type(io)
    catch e
        close(io)
        rethrow(e)
    end
    ret
end

function _guess_file_type(io::IOStream)
    hdr = read(io, Array(Uint8, 10))

    beginswith(hdr, FILE_HDR_NPY)               && return FILE_TYPE_NPY
    beginswith(hdr, FILE_HDR_AAGRID)            && return FILE_TYPE_AAGRID
    beginswith(hdr, FILE_HDR_INCL_PAIRS_AAGRID) && return FILE_TYPE_INCL_PAIRS_AAGRID
    beginswith(hdr, FILE_HDR_INCL_PAIRS)        && return FILE_TYPE_INCL_PAIRS
    return FILE_TYPE_TXTLIST
end


#######################################
# AAGRID
#######################################
type FileAAGridHeader
    ncols::Int
    nrows::Int
    xllcorner::Float64
    yllcorner::Float64
    cellsize::Float64
    nodata::NoData

    file_type::Int
    file_name::String

    FileAAGridHeader() = new(0, 0, 0.0, 0.0, 0.0, nothing, [], 0, "")

    function FileAAGrid(filename::String)
        ncols, nrows, xllcorner, yllcorner, cellsize, nodata, file_type = _ascii_grid_read_header(filename)
        new(ncols, nrows, xllcorner, yllcorner, cellsize, nodata, file_type, filename)
    end

    function _ascii_grid_read_header(filename::String)
        _check_file_exists(filename)
        io = _open_auto_uncompress(filename)
        try
            file_type = _guess_file_type(io)
            if file_type == FILE_TYPE_NPY
                file_base, file_extension = splitext(filename)
                filename = file_base + ".hdr"
                ncols, nrows, xllcorner, yllcorner, cellsize, nodata, _file_type = _ascii_grid_read_header(filename)
            else
                try
                    ncols = int(split(readline(io))[2])
                    nrows = int(split(readline(io))[2])
                    xllcorner = float(split(readline(io))[2])
                    yllcorner = float(split(readline(io))[2])
                    cellsize = float(split(readline(io))[2])
                catch e
                    err(iologger, "Error reading ASCII grid. $(e)")
                    error("Unable to read ASCII grid: \"$(filename)\".")
                end
               
                nodata = nothing 
                next_line = split(readline(io))
                if length(next_line) == 2
                    try
                        nodata = int(next_line[2])
                    catch
                        try
                            nodata = float(next_line[2])
                        end
                    end
                end   
            end
        finally
            close(io)
        end

        return ncols, nrows, xllcorner, yllcorner, cellsize, nodata, file_type
    end
end

type FileAAGrid
    hdr::FileAAGridHeader
    pmap::Array
    data_type::String

    FileAAGrid() = new(FileAAGridHeader(), [])

    function FileAAGrid(filename::String, data_type="float")
        hdr = FileAAGridHeader(filename)

        if hdr.file_type == FILE_TYPE_NPY
            pmap = np.load(filename, mmap_mode=nothing)
            pmap = convert(Array{Float64, 2}, pmap)
        else
            if hdr.nodata == nothing
                pmap = np.loadtxt(filename, skiprows=5, dtype=data_type)
            else
                pmap = np.loadtxt(filename, skiprows=6, dtype=data_type)
                pmap[find(x->(x==nodata), pmap)] = -9999
            end
        end

        (hdr.nrows == 1) && (pmap = reshape(pmap, 1, length(pmap)))
        (hdr.ncols == 1) && (pmap = reshape(pmap, length(pmap), 1))
        new(hdr, pmap, data_type)
    end
end

function write(filename::String, aagrid::FileAAGrid; file_type=aagrid.hdr.file_type, compress=false)
    if file_type == FILE_TYPE_NPY
        np.save(filename, aagrid.pmap)
    else
        io = compress ? GZip.open(filename, "w") : open(filename, "w")
        try
            write(io, aagrid)
        finally
            close(io)
        end
    end
end

function write(io::IOStream, aagrid::FileAAGrid)
    hdr = aagrid.hdr
    println(io, "ncols         $(hdr.ncols)")
    println(io, "nrows         $(hdr.nrows)")
    println(io, "xllcorner     $(hdr.xllcorner)")
    println(io, "yllcorner     $(hdr.yllcorner)")
    println(io, "cellsize      $(hdr.cellsize)")
    (hdr.nodata != nothing) && println(io, "NODATA_value  $(hdr.nodata)")

    writedlm(io, aagrid.pmap, ' ')
end

#######################################
# TXT LIST
#######################################

type FileTxtList
end

