
loggers = Dict{String, Logger}()

function getlogger(name::String)
    names = rsplit(name, ".", 2)
    parent = (length(names) > 1) ? getlogger(names[1]) : Logging._root
     
    haskey(loggers, name) && return loggers[name]
    loggers[name] = Logger(name, Logging.DEBUG, STDOUT, parent)
end

function configure_loggers(args...)
    configure(Logging._root, args...)
    for name in ["circuitscape", "cfg"]
        configure_logger(name, args...)
    end
end

configure_logger(name::String, args...) = configure(getlogger(name, args...))

