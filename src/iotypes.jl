# Circuitscape file types:
# - resistance/conductance map (HabitatRasterMap)
# - focal nodes (point/region)
# - short circuit region file
# - include/exclude pairs
# - current sources
# - ground points/resistances
# - raster mask file
# - source strengths

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
    print("Habitat Raster Map as ")
    show(hab.hdr)
    println("nodata: $(hab.nodata)")
    show(hab.cond)
end



type FocalPoints
    data::Array{Int32,2}
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

    polygons(data::Array{Int32,2}) = (length(unique(data[:,1])) < size(data)[1])
end

point_ids(fp::FocalPoints) = fp.data[:,1]


function show(io::IO, fp::FocalPoints)
    print("FocalPoints ")
    show(fp.data)
end

type InclExclPairs
end


