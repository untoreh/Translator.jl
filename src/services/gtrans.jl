mutable struct GoogleTrans
    mod::OptPy
    tr::OptPy
end

srv_sym = :googletrans
srv_val = Val{srv_sym}


if isunset(srv_sym)
    const googletrans =  GoogleTrans(nothing, nothing)
end

@typesderef function init(::srv_val)
	let f() = begin
        googletrans.mod = pyimport("googletrans")
        googletrans.tr = googletrans.mod.Translator(
            service_urls = [
                "translate.google.com",
                "translate.google.de",
                "translate.google.es",
                "translate.google.fr",
                "translate.google.it",
            ],
        )
    end
        try
            f()
        catch
            Conda.pip("install --user --pre", "googletrans")
            f()
        end
    end

end

@typesderef function init_translator(::srv_val, targets=TLangs, source=SLang.code)
    init(srv_sym)
    tr = TranslatorDict()
    for (_, tlang) in targets
        tr[Pair(source, tlang)] = googletrans.tr.translate
    end
end

@typesderef function translate(str::StrOrVec, ::srv_val; src=SLang.code, target::String, TR::TranslatorDict)
    let t_fn(x) = TR[Pair(SLang, target)](x, src = src, dest = target).text
        @__MODULE__()._translate(str, t_fn)
    end
end

push!(REG_SERVICES, srv_sym)
