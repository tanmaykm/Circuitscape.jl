# Circuitscape file types:
# - resistance/conductance map (HabitatRasterMap)
# - focal nodes (point/region)
# - short circuit region file
# - include/exclude pairs
# - current sources
# - ground points/resistances
# - raster mask file
# - source strengths

# =================================
# Habitat representations
# =================================
# TODO: support reclassification
type HabitatRasterMap
    cond::Array{Float64,2}
    hdr::FileAAGridHeader
    nodata::Real
    
    function HabitatRasterMap(filename::String, resistance::Bool)
        grid = FileAAGrid(filename)
        hdr = grid.hdr
        data = grid.data

        if resistance
            # convert data into conductance format
            (findfirst(data, 0) > 0) && error("Zero resistance values are not currently supported for habitat maps.  Use a short-circuit region file instead.")
            cond = 1 ./ data
        else
            cond = data
        end

        nodata = (nothing != hdr.nodata) ? -9999 : hdr.nodata
        cond[find(x->(x==nodata), data)] = 0

        new(cond, hdr, nodata)
    end
end

function show(io::IO, hab::HabitatRasterMap)
    print(io, "Habitat Raster Map as ")
    show(hab.hdr)
    println(io, "nodata: $(hab.nodata)")
    show(hab.cond)
end


# ==================================
# Habitat
# ==================================
type Habitat
    # the node map
    node_map::Array{Int,2}
    num_nodes::Int

    # conductances between nodes. store as sparse matrix?
    node1::Array{Int,1}
    node2::Array{Int,1}
    g::Array{Float64,1}

    ccs::Array{Array{Int,1},1}     # the connected component list
    component_map::Array{Int,2}    # can be Int16 probably
    num_components::Int

    # remember parameters
    connect_using_avg_resistances::Bool
    connect_four_neighbors_only::Bool
end

function Habitat(rastmap::HabitatRasterMap, connect_using_avg_resistances::Bool=false, connect_four_neighbors_only::Bool=false)
    cond = rastmap.cond
    sz = size(cond)
   
    # create a grid of node numbers corresponding to raster pixels with non-zero conductances 
    # Note: node ids are allocated in column major order. Should not matter for the calculations though.
    node_map = zeros(Int, sz...)
    nzidxs = findn(reshape(cond, prod(sz)))[1]
    
    num_nodes = length(nzidxs)
    node_map[nzidxs] = 1:num_nodes

    # create the node conductance graph
    node1, node2, cond = node_conductances(cond, node_map, connect_using_avg_resistances, connect_four_neighbors_only)
    gr = simple_adjlist(num_nodes, is_directed=false)
    for idx in 1:length(node1)
        add_edge!(gr, node1[idx], node2[idx])
    end

    # find connected components and create component map
    # we can probably store only the compact form (ccs)
    ccs = connected_components(gr)
    component_map = zeros(Int, sz...)
    for compid in 1:length(ccs)
        component_map[findin(node_map, ccs[compid])] = compid
    end

    Habitat(node_map, num_nodes, node1, node2, cond, ccs, component_map, length(ccs), connect_using_avg_resistances, connect_four_neighbors_only)
end

function show(io::IO, hab::Habitat)
    println(io, "Habitat with $(hab.num_nodes) nodes, $(hab.num_components) components")
end


# Calculates conductances between adjacent nodes given a raster conductance map.
# Returns an adjacency matrix with values representing node-to-node conductance values.
function node_conductances(gmap::Array{Float64,2}, node_map::Array{Int,2}, connect_using_avg_resistances::Bool, connect_four_neighbors_only::Bool)
    s_horiz, t_horiz = _neighbors_horz(gmap)
    s_vert, t_vert = _neighbors_vert(gmap)

    s = [s_horiz, s_vert]
    t = [t_horiz, t_vert]

    g1 = gmap[s]
    g2 = gmap[t]

    if connect_using_avg_resistances
        cond = 1 ./ (((1 ./ g1) .+ (1 ./ g2)) ./ 2)
    else
        cond = (g1 .+ g2) ./ 2
    end
   
    if !connect_four_neighbors_only
        s_dr, t_dr = _neighbors_diag1(gmap)
        s_dl, t_dl = _neighbors_diag2(gmap)

        s_d = [s_dr, s_dl]
        t_d = [t_dr, t_dl]

        g1 = gmap[s_d]
        g2 = gmap[t_d]

        if connect_using_avg_resistances
            cond_d = 1 ./ (sqrt(2) .* ((1 ./ g1) + (1 ./ g2) ./ 2))
        else
            cond_d = (g1 .+ g2) ./ (2 * sqrt(2))
        end

        s = [s, s_d]
        t = [t, t_d]
        cond = [cond, cond_d]
    end

    node1 = node_map[s]
    node2 = node_map[t]
    (node1, node2, cond)
end

function _neighbors_horz(gmap::Array{Float64,2})
    m,n = size(gmap)

    gmap_l = gmap[:, 1:(n-1)]
    gmap_r = gmap[:, 2:n]

    gmap_lr = convert(Array{Bool,2}, gmap_l .* gmap_r)
    gmap_lr = hcat(gmap_lr, falses(m))
    
    s_horiz = find(gmap_lr)
    t_horiz = s_horiz .+ m

    return (s_horiz, t_horiz)
end

function _neighbors_vert(gmap::Array{Float64,2})
    m,n = size(gmap)

    gmap_u = gmap[1:(m-1), :]
    gmap_d = gmap[2:m, :]

    gmap_ud = convert(Array{Bool,2}, gmap_u .* gmap_d)
    gmap_ud = vcat(gmap_ud, falses(1,n))

    s_vert = find(gmap_ud)
    t_vert = s_vert .+ 1

    return (s_vert, t_vert)
end

function _neighbors_diag1(gmap::Array{Float64,2})
    m,n = size(gmap)

    gmap_ul = gmap[1:(m-1), 1:(n-1)]
    gmap_dr = gmap[2:m, 2:n]

    gmap_uldr = convert(Array{Bool,2}, gmap_ul .* gmap_dr)
    gmap_uldr = vcat(hcat(gmap_uldr, falses(m-1)), falses(1,n))

    s_dr = find(gmap_uldr)
    t_dr = s_dr .+ (m+1)

    return (s_dr, t_dr)
end

function _neighbors_diag2(gmap::Array{Float64,2})
    m,n = size(gmap)

    gmap_ur = gmap[1:(m-1), 2:n]
    gmap_dl = gmap[2:m, 1:(n-1)]

    gmap_urdl = convert(Array{Bool,2}, gmap_ur .* gmap_dl)
    gmap_urdl = vcat(hcat(falses(m-1), gmap_urdl), falses(1,n))

    s_dl = find(gmap_urdl)
    t_dl = s_dl .- (m-1)

    return (s_dl, t_dl)
end

# ==================================
# FocalPoints
# ==================================
type FocalPoints
    data::Array{Int,2}
    polygons::Bool

    function FocalPoints(filename::String)
        ftype = _guess_file_type(filename)

        # TODO: implement resampling to match habitat size
        if ftype == FILE_TYPE_AAGRID
            grid = FileAAGrid(filename, "int32")
            hdr = grid.hdr
            data = grid.data
            nodata = (nothing != hdr.nodata) ? -9999 : hdr.nodata
            data[find(x->(x==nodata), data)] = 0    # ignore nodata values
            data[find(x->(x < 0), data)] = 0        # ignore negative point ids

            rows,cols,vals = findnz(data)
            data = hcat(vals, rows, cols)
            data = sortrows(data)

            return new(data, polygons(data))

        elseif ftype == FILE_TYPE_TXTLIST
            error("txtlist format for focal points not supported yet")
        else
            error("Unknown file type for focal points")
        end
    end

    polygons(data::Array{Int,2}) = (length(unique(data[:,1])) < size(data)[1])
end

point_ids(fp::FocalPoints) = fp.data[:,1]
num_points(fp::FocalPoints) = size(fp.data)[1]

function show(io::IO, fp::FocalPoints)
    print(io, "FocalPoints ")
    show(fp.data)
end

# Checks to see if there are at least two focal points in a given component.
function has_focal_points(fp::FocalPoints, hab::Habitat, comp::Int)
    numfp = num_points(fp)
    node_map = hab.node_map
    fpl = fp.data
    comp_nodes = hab.ccs[comp]

    for fpid1 in 1:numfp
        # find the node id of fp 1
        nid1 = node_map[fpl[fpid1, 2:3]...]
        ((nid1 == 0) || !(nid1 in comp_nodes)) && continue
        for fpid2 in (fpid1+1):numfp
            # find the node id of fp 2
            nid2 = node_map[fpl[fpid2, 2:3]...]
            # return true if both are valid nodes, and both belong to component comp
            (nid2 > 0) && (nid2 in comp_nodes) && (return true)
        end
    end
    return false
end

function focal_points(fp::FocalPoints, hab::Habitat, comp::Int)
    numfp = num_points(fp)
    node_map = hab.node_map
    fpl = fp.data
    comp_nodes = hab.ccs[comp]

    for fpid1 in 1:numfp
        # find the node id of fp 1
        nid1 = node_map[fpl[fpid1, 2:3]...]
        ((nid1 == 0) || !(nid1 in comp_nodes)) && continue
        for fpid2 in (fpid1+1):numfp
            # find the node id of fp 2
            nid2 = node_map[fpl[fpid2, 2:3]...]
            # return true if both are valid nodes, and both belong to component comp
            (nid2 > 0) && (nid2 in comp_nodes) && produce((nid1, nid2))
        end
        produce((nid1, -1))
    end
end

type InclExclPairs
end


