
function solve_pairwise(hab::Habitat, fp::FocalPoints)

    fp.polygons && error("Polygons in focal points are not supported yet")

    # only the shortcut method is implemented
    numpts = num_points(fp)
    shortcut_resistances = -1 .* ones(numpts, numpts)
    resistances = -1 .* ones(numpts, numpts)
   
    println("Graph has $(hab.num_nodes) nodes, $(numpts) focal nodes and $(hab.num_components) components.") 

    for comp in 1:hab.num_components
        println("component $comp")
        for pts in Task(()->Circuitscape.focal_points(fp, hab, comp))
            println("\t$(pts)")
        end
    end
    
end

