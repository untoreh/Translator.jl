mutable struct Deep
    mod::OptPy
    tr::Dict{Symbol, OptPy}
    apis::Tuple
    provider::Symbol
end

srv_sym = :deep
srv_val = Val{srv_sym}

if isunset(srv_sym, :mod)
    const deep = Deep(nothing, Dict(),
                (:GoogleTranslator,
                 :MicrosoftTranslator,
                 :PonsTranslator,
                 :LingueeTranslator,
                 :MyMemoryTranslator,
                 :YandexTranslator,
                 :DeepL,
                 :QCRI,
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
    for (_, tlang) in targets
        tr[Pair(source, tlang)] = deep.mod[deep.provider](source=source, target=tlang)
    end
    tr
end

@typesderef function translate(str::String, ::srv_val; src::String=SLang.code, target::String, TR::TranslatorDict)
    # @show "translating string $str"
    @__MODULE__()._translate(str, TR[Pair(src, target)].translate)
end

push!(REG_SERVICES, srv_sym)
