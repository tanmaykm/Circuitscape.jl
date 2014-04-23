using Circuitscape

const FILE_CELLMAP_ASC = joinpath("data_files", "cellmap.asc")
const FILE_CELLMAP_ASC_GZ = joinpath("data_files", "cellmap.asc.gz")
const FILE_INCLUDE_MATRIX = joinpath("data_files", "include_matrix.txt")

@assert false == try Circuitscape._check_file_exists("cellmap.asc") end
@assert Circuitscape._check_file_exists(FILE_CELLMAP_ASC)

@assert Circuitscape.FILE_TYPE_AAGRID == Circuitscape._guess_file_type(FILE_CELLMAP_ASC)
@assert Circuitscape.FILE_TYPE_AAGRID == Circuitscape._guess_file_type(FILE_CELLMAP_ASC_GZ)
@assert Circuitscape.FILE_TYPE_INCL_PAIRS_AAGRID == Circuitscape._guess_file_type(FILE_INCLUDE_MATRIX)
@assert Circuitscape.FILE_TYPE_INCL_PAIRS == Circuitscape._guess_file_type(FILE_INCLUDE_MATRIX)

f = FileAAGrid(FILE_CELLMAP_ASC)
@assert f.hdr.ncols == 10
@assert f.hdr.nrows == 10
@assert f.hdr.nodata == -9999
@assert f.data_type == "float"
@assert f.data[1,1] == 1.0

fname = tempname()
write(fname, f)
f = FileAAGrid(fname)
rm(fname)
@assert f.hdr.ncols == 10
@assert f.hdr.nrows == 10
@assert f.hdr.nodata == -9999
@assert f.data_type == "float"
@assert f.data[1,1] == 1.0

fname = "$(tempname()).gz"
write(fname, f, compress=true)
f = FileAAGrid(fname)
rm(fname)
@assert f.hdr.ncols == 10
@assert f.hdr.nrows == 10
@assert f.hdr.nodata == -9999
@assert f.data_type == "float"
@assert f.data[1,1] == 1.0

