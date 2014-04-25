using Circuitscape

const FILE_CELLMAP_ASC = joinpath("sample1", "cellmap.asc")
const FILE_POINTS_ASC = joinpath("sample1", "points.asc")

h = Circuitscape.HabitatRasterMap(FILE_CELLMAP_ASC, true)
hab = Circuitscape.Habitat(h)
fp = Circuitscape.FocalPoints(FILE_POINTS_ASC)
Circuitscape.solve_pairwise(hab, fp)

