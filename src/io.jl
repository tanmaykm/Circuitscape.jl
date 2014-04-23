
typealias NoData Union(Nothing,Number)

const FILE_TYPE_NPY                 = 1
const FILE_TYPE_AAGRID              = 2
const FILE_TYPE_TXTLIST             = 3
const FILE_TYPE_INCL_PAIRS_AAGRID   = 4
const FILE_TYPE_INCL_PAIRS          = 5

const STR_FILE_TYPES = ["numpy", "aagrid", "text list", "include grid", "include pairs"]

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
        hdr = read!(f, Array(Uint8, 3))
        seek(f, 0)
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
        return _guess_file_type(io)
    catch ex
        close(io)
        rethrow(ex)
    end
end

function _guess_file_type(io::IO)
    hdr = read!(io, Array(Uint8, 10))
    seek(io, 0)

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

    function FileAAGridHeader(filename::String="")
        ncols, nrows, xllcorner, yllcorner, cellsize, nodata, file_type = _ascii_grid_read_header(filename)
        new(ncols, nrows, xllcorner, yllcorner, cellsize, nodata, file_type, filename)
    end

    function _ascii_grid_read_header(filename::String)
        _check_file_exists(filename)

        io = _open_auto_uncompress(filename)

        try
            ncols = nrows = 0
            xllcorner = yllcorner = cellsize = 0.0
            nodata = nothing

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

            return ncols, nrows, xllcorner, yllcorner, cellsize, nodata, file_type

        finally
            close(io)
        end
    end
end

function show(io::IO, hdr::FileAAGridHeader)
    println("$(STR_FILE_TYPES[hdr.file_type]) $(hdr.nrows)x$(hdr.ncols) ($(hdr.file_name))")
    println("llcorner: ($(hdr.xllcorner),$(hdr.yllcorner)). cellsize: $(hdr.cellsize). nodata: $(hdr.nodata)") 
end


type FileAAGrid
    hdr::FileAAGridHeader
    data::Array
    data_type::String

    FileAAGrid() = new(FileAAGridHeader(), [])

    function FileAAGrid(filename::String, data_type="float")
        hdr = FileAAGridHeader(filename)

        if hdr.file_type == FILE_TYPE_NPY
            data = np.load(filename, mmap_mode=nothing)
            data = convert(Array{Float64, 2}, data)
        else
            if hdr.nodata == nothing
                data = np.loadtxt(filename, skiprows=5, dtype=data_type)
            else
                data = np.loadtxt(filename, skiprows=6, dtype=data_type)
                data[find(x->(x==hdr.nodata), data)] = -9999
            end
        end

        (hdr.nrows == 1) && (data = reshape(data, 1, length(data)))
        (hdr.ncols == 1) && (data = reshape(data, length(data), 1))
        new(hdr, data, data_type)
    end
end

function show(io::IO, aag::FileAAGrid)
    print(io, "$(aag.data_type) ")
    show(io, aag.hdr)
    show(io, aag.data)
end

function write(filename::String, aagrid::FileAAGrid; file_type=aagrid.hdr.file_type, compress=false)
    if file_type == FILE_TYPE_NPY
        np.save(filename, aagrid.data)
    else
        io = compress ? GZip.open(filename, "w") : open(filename, "w")
        try
            write(io, aagrid)
        finally
            close(io)
        end
    end
end

function write(io::IO, aagrid::FileAAGrid)
    hdr = aagrid.hdr
    println(io, "ncols         $(hdr.ncols)")
    println(io, "nrows         $(hdr.nrows)")
    println(io, "xllcorner     $(hdr.xllcorner)")
    println(io, "yllcorner     $(hdr.yllcorner)")
    println(io, "cellsize      $(hdr.cellsize)")
    (hdr.nodata != nothing) && println(io, "NODATA_value  $(hdr.nodata)")

    writedlm(io, aagrid.data, ' ')
end

#######################################
# TXT LIST
#######################################

type FileTxtList
#    data::Array
#    data_type::String
#
#    file_name::String
#
#    function FileTxtList(filename::String, habitat_size::FileAAGridHeader, data_type::String="float")
#        typ = (data_type == "float") ? Float64 : (data_type == "int") ? Int : error("invalid data type $data_type")
#        data = readdlm(filename)
#
#        data2 = ceil(habitat_size.nrows - (data[:,3] - habitat_size.yllcorner) / habitat_size.cellsize) - 1
#        data3 = ceil((data[:,2] - habitat_size.xllcorner) / habitat_size.cellsize) - 1
#        data[:,2] = data2
#        data[:,3] = data3
#        data = convert(Array{typ, 2}, data)
#
#        new(data, data_type, filename)
#    end
end

