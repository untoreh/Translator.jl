mutable struct GoogleTrans
    mod::OptPy
    tr::OptPy
end

srv_sym = :googletrans
srv_val = Val{srv_sym}
GTrans = Tuple{srv_val, TranslatorDict}


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

@typesderef function init_translator(srv::srv_val, targets=TLangs, source=SLang.code)
    init(srv)
    tr = TranslatorDict()
    for lang in targets
        tr[(src=source, trg=lang.code)] = googletrans.tr.translate
    end
    (srv, tr)
end

@typesderef function get_tfun(lang::LangPair, TR::GTrans)
    txt -> TR[2][lang](txt, src = lang.src, dest = lang.trg).text
end

push!(REG_SERVICES, srv_sym)
