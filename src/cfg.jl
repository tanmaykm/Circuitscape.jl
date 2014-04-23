const FILE_PATH_PROPS = ["polygon_file", "source_file", "ground_file", "mask_file", "output_file", "habitat_file", "point_file", "reclass_file"]
const DEFAULT_CFG     = {
        "Version" => {
            "version" => "unknown"
        },
        "Connection scheme for raster habitat data" => {
            "connect_four_neighbors_only" => false, 
            "connect_using_avg_resistances" => false,
        },
        "Short circuit regions (aka polygons)" => {
            "use_polygons" => false,
            "polygon_file" => "(Browse for a short-circuit region file)"
        },                  
        "Options for advanced mode" => {
            "source_file" => "(Browse for a current source file)", 
            "ground_file" => "(Browse for a ground point file)", 
            "ground_file_is_resistances" => true, 
            "use_unit_currents" => false, 
            "use_direct_grounds" => false,
            "remove_src_or_gnd" => "keepall" 
        }, 
        "Mask file" => {
            "mask_file" => nothing, 
            "use_mask" => false
        }, 
        "Calculation options" => {
            "preemptive_memory_release" => false,
            "low_memory_mode" => false,
            "parallelize" => false,          # can parallelize if true. It may be overridden internally to false based on os support and suitability of the problem.
            "max_parallel" => 0,            # passing 0 results in using all available cpus
            "print_timings" => false, 
            "print_rusages" => false, 
            "solver" => "cg+amg"
        }, 
        "Options for one-to-all and all-to-one modes" => {
            "use_variable_source_strengths" => false, 
            "variable_source_file" => nothing
        }, 
        "Output options" => {
            "set_null_currents_to_nodata" => false, 
            "output_file" => "(Choose a base name for output files)", 
            "write_cum_cur_map_only" => false, 
            "log_transform_maps" => false, 
            "write_max_cur_maps" => false, 
            "compress_grids" => false, 
            "set_null_voltages_to_nodata" => false, 
            "set_focal_node_currents_to_zero" => false, 
            "write_volt_maps" => false, 
            "write_cur_maps" => false
        }, 
        "Habitat raster or graph" => {
            "habitat_map_is_resistances" => true,
            "habitat_file" => "(Browse for a resistance file)"
        }, 
        "Circuitscape mode" => {
            "scenario" => "not entered", 
            "data_type" => "raster"
        }, 
        "Options for pairwise and one-to-all and all-to-one modes" => {
            "use_included_pairs" => false, 
            "included_pairs_file" => "(Browse for a file with pairs to include or exclude)", 
            "point_file" => "(Browse for file with locations of focal points or regions)"
        },
        "Options for reclassification of habitat data" => {
            "use_reclass_table" => false,
            "reclass_file" => "(Browse for file with reclassification data)"
        },
        "Logging Options" => {
            "profiler_log_file" => nothing,      # file to log timing and rusage profiling results 
            "log_file" => nothing,               # file to log regular log messages
            "log_level" => "INFO",           # one of FATAL, ERROR, WARN, INFO, DEBUG
            "screenprint_log" => false        # whether to print logs to console (stdout)
        }
    }

const CHECKS_AND_MESSAGES = {
        "scenario" => "Please choose a scenario",
        "habitat_file" => "Please choose a resistance file",
        "output_file" => "Please choose an output file name",
        "point_file" => "Please choose a focal node file",
        "source_file" => "Please enter a current source file",
        "ground_file" => "Ground point file does not exist!",
        "reclass_file" => "Please choose a file with reclassification data",
        "polygon_file" => "Please enter a short-circuit region file or uncheck this option in the Options menu"
    }


type CSCfg
    inifile::Inifile
    val_dict::IniFile.HTSS
    logger::Logger
    filename::String
    
    function CSCfg(cfgfile::String="", rel_to_abs::String="")
        ret = new()
        ret.logger = getlogger("circuitscape.cfg")
        debug(ret.logger, "created CSCfg with config file \"$cfgfile\"")
        defaults = IniFile.HTSS()
        for section_vals in values(DEFAULT_CFG)
            merge!(defaults, section_vals)
        end

        inifile = Inifile()
        !isempty(cfgfile) && read(inifile, cfgfile)
        inifile.defaults = defaults

        ret.inifile = inifile
        ret.val_dict = as_dict(ret, rel_to_abs)
        ret.filename = cfgfile
        ret
    end
end

function show(io::IO, cfg::CSCfg)
    println(io, "CSCfg with $(length(cfg.val_dict)) entries")
    if !isempty(cfg.filename)
        println(io, "file: $(cfg.filename)")
    end
end

approp(val) = val
function approp(val::String)
    ((val == "nothing") || (val == "None")) && (return nothing)
    try
        val = parsebool(val)
    catch
        try
            val = parseint(val)
        catch
            try
                val = parsefloat(val)
            catch
                # ignore
            end
        end
    end
    val
end

function parsebool(str::String)
    str = lowercase(str)
    (str == "true") && return true 
    (str == "false") && return false
    error("invalid boolean representation")
end

function as_dict(cscfg::CSCfg, rel_to_abs::String)
    ret = IniFile.HTSS()
    for (section_name, htss) in DEFAULT_CFG
        for (key, val) in htss
            cfgval = get(cscfg.inifile, section_name, key, val)
            if key in FILE_PATH_PROPS
                if (cfgval == nothing) || (val == cfgval)
                    cfgval = ""
                elseif !isempty(rel_to_abs) && !isabspath(cfgval)
                    cfgval = joinpath(rel_to_abs, cfgval)
                end
            end
            ret[key] = approp(cfgval)
        end
    end
    ret
end

function write(io::IO, cscfg::CSCfg, pretty_print::Bool=true)
    write_space = false
    for (section_name, htss) in DEFAULT_CFG
        if pretty_print
            if write_space
                println(io, "")
            else
                write_space = true
            end
        end
        println(io, "[$section_name]")

        for (key, val) in htss
            cfgval = get(cscfg, key)
            println(io, "$key=$cfgval")
        end
    end
end

get(cscfg::CSCfg, key::String) = cscfg.val_dict[key]
set(cscfg::CSCfg, key::String, val::IniFile.INIVAL) = (cscfg.val_dict[key] = approp(val))
function get(cscfg::CSCfg, key::String, typ::Type)
    v = get(cscfg, key)
    vtyp = typeof(v)
    if isa(v, String) && !issubtype(vtyp, typ) 
        lcv = lowercase(v)
        ((lcv == "none") || (lcv == "nothing")) && (return nothing)
        if (typ == Bool)
            (v == "false") && (return false)
            (v == "true") && (return true)
            error("Invalid boolean value $v")
        else 
            return convert(typ, v)
        end
    end
    return v
end

