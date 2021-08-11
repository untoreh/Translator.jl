mutable struct PyTranslators
    mod::OptPy
    apis::Tuple
    provider::Symbol
end

srv_sym = :pytranslators
srv_val = Val{srv_sym}

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

@typesderef function init_translator(::srv_val; source=SLang.code, targets=TLangs)
    tr = TranslatorDict()
    for (_, tlang) in targets
        tr[Pair(source, tlang)] = pytranslators.mod[pytranslators.provider]
    end
    tr
end

@typesderef function translate(str::StrOrVec, ::srv_val; src=SLang.code, target::String,  TR::TranslatorDict)
    TR[Pair(src, target)](x, to_language=target)(str)
end

push!(REG_SERVICES, srv_sym)
