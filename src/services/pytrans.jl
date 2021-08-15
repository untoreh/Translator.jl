srv_sym = :pytrans
srv_val = Val{srv_sym}
PyTransTR = Tuple{srv_val, TranslatorDict}
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

@typesderef function init(::srv_val)
	try
        pytrans.mod = pyimport("translate")
    catch
        Conda.pip("install --user", "git+git://github.com/terryyin/translate-python")
        pytrans.mod = pyimport("translate")
    end

end

@typesderef function init_translator(::srv_val; targets=TLangs, source=SLang.code)
	init(srv_sym)
    tr = TranslatorDict()
    for lang in targets
        let tlang = lang.code
            tr[(src=source, trg=tlang)] =
                pytrans.mod.Translator(from_lang = source,
                                       to_lang=tlang,
                                       provider=pytrans.provider).translate
        end
    end
    (srv, tr)
end

@typesderef function get_tfun(lang::LangPair, TR::PyTransTR)
    TR[2][lang]
end

push!(REG_SERVICES, srv_sym)
