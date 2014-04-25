using Circuitscape

const FILE_CELLMAP_ASC = joinpath("data_files", "cellmap.asc")
const FILE_POINTS_ASC = joinpath("data_files", "points.asc")

hab = Circuitscape.HabitatRasterMap(FILE_CELLMAP_ASC, true)
@assert hab.nodata == -9999
@assert hab.hdr.ncols == 10
@assert hab.hdr.nrows == 10
@assert hab.hdr.nodata == -9999
@assert hab.cond[1,1] == 1.0
@assert hab.cond[1,2] == 0.5

fp = Circuitscape.FocalPoints(FILE_POINTS_ASC)
@assert size(fp.data) == (10,3)
@assert fp.data[3,1] == 3
@assert fp.data[10,2] == 10


