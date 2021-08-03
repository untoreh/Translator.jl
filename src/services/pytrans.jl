include("common.jl")

srv_sym = :pytrans
srv_val = Val{srv_sym}
provider = :mymemory
pytrans_dict = Dict{Tuple{Symbol,String,String},OptPy}

mutable struct PyTrans
    mod::OptPy
    # target lang translator instances
    tr::pytrans_dict
    provider::Symbol
end

if isunset(srv_sym, :mod)
    const pytrans = PyTrans(nothing, pytrans_dict(), provider)
end

function init(::srv_val)
	try
        pytrans.mod = pyimport("translate")
    catch
        Conda.pip("install --user", "git+git://github.com/terryyin/translate-python")
        pytrans.mod = pyimport("translate")
    end

end

function init_translator(SLang, TLangs, ::srv_val)
	init(srv_sym)
    tr = Translator()
    for (_, code) in TLangs
        tr[Pair(SLang, code)] = pytrans.mod.Translator(from_lang = SLang,
                                   to_lang=code,
                                   provider=pytrans.provider).translate
    end
    tr
end

function translate(str::String; src::String=SLang, target::String, TR::Translator, srv::srv_val)
    @__MODULE__()._translate(str, TR[Pair(src, target)])
end


push!(REG_SERVICES, srv_sym)
