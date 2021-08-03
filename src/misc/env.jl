function _add_python_user_path()
    pysys = pyimport("sys")
    py_v = pysys.version_info
    py_path = "python$(py_v[1]).$(py_v[2])"
    py_sys_path = PyVector(pysys."path")
    # @show py_path
    let home = ENV["HOME"]
        pushfirst!(py_sys_path, "$home/.local" * "/lib/$py_path/site-packages")
        pushfirst!(py_sys_path, "")
    end
    @warn "using python $py_v"
end

function _init_env()
    Conda.pip_interop(true)
    # we need to add paths to python runtime because pycall doesn't include them
    _add_python_user_path()
    global ENV_INITIALIZED = true
end

ENV_INITIALIZED = false
