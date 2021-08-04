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

function init(::Val{:pytranslators})
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

function init_translator(SLang, TLangs, ::srv_val)
    tr = Translator()
    for (_, code) in TLangs
        tr[Pair(SLang, code)] = pytranslators.mod[pytranslators.provider]
    end
    tr
end

function translate(str::StrOrVec, ::srv_val; src=SLang, target::String,  TR::Translator)
    let t_fn(x) = TR[Pair(src, target)](x, to_language=target)
        @__MODULE__()._translate(str, t_fn)
    end
end

push!(REG_SERVICES, srv_sym)
