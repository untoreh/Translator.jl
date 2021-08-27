mutable struct PyTranslators
    mod::OptPy
    apis::Tuple
    provider::Symbol
end

srv_sym = :pytranslators
srv_val = Val{srv_sym}
PyTranslatorsTR = Tuple{srv_val, TranslatorDict}

if isunset(srv_sym, :mod)
    const pytranslators = PyTranslators(
        nothing,
        (:google, :bing, :yandex, :alibaba, :baidu, :deepl, :sogou, :tencent, :youdao),
        :google
    )
end

@typesderef function init(::Val{:pytranslators})
    let f() = begin
	    pytranslators.mod = pyimport("translators")
    end
        try
	        f()
        catch
	        Conda.pip("install --user", "translators")
            f()
        end
    end

end

@typesderef function init_translator(srv::srv_val; source=SLang.code, targets=TLangs)
    init(srv)
    tr = TranslatorDict()
    let p = pytranslators.mod[pytranslators.provider]
        for lang in targets
            tr[(src=source, trg=lang.code)] = p
        end
    end
    (srv, tr)
end

@typesderef function get_tfun(lang::LangPair, TR::PyTranslatorsTR)
    x -> TR[2][lang](x, from_language=lang.src, to_language=lang.trg)
end

push!(REG_SERVICES, srv_sym)
