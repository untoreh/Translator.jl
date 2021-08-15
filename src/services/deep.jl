mutable struct Deep
    mod::OptPy
    tr::Dict{Symbol, OptPy}
    apis::Tuple
    provider::Symbol
end


srv_sym = :deep
srv_val = Val{srv_sym}
DeepTranslator = Tuple{srv_val, TranslatorDict}

if isunset(srv_sym, :mod)
    const deep = Deep(nothing, Dict(),
                      (:GoogleTranslator,
                       :LingueeTranslator,
                       :MyMemoryTranslator,
                       # :MicrosoftTranslator,
                       # :PonsTranslator,
                       # :YandexTranslator,
                       # :DeepL,
                       # :QCRI,
                       :single_detection,
                       :batch_detection),
                      :GoogleTranslator)
end

@typesderef function init(::srv_val)
        try
            deep.mod = pyimport("deep_translator")
        catch
            Conda.pip("install", "deep_translator")
            deep.mod = pyimport("deep_translator")
        end
        for cls in deep.apis
            deep.tr[cls] = deep.mod[cls]
        end
end

@typesderef function init_translator(srv::srv_val; targets=TLangs, source=SLang.code)
	init(srv)
    tr = TranslatorDict()
    for lang in targets
        let tlang = lang.code
            tr[(src=source, trg=tlang)] = deep.mod[deep.provider](source=source, target=tlang)
        end
    end
    (srv, tr)
end

@typesderef function get_tfun(lang::LangPair, TR::DeepTranslator)
    # @show "translating string $str"
    TR[2][lang].translate
end

push!(REG_SERVICES, srv_sym)
