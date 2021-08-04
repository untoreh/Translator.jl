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

function init(::Val{:deep})
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

function init_translator(SLang, TLangs, ::srv_val)
	init(srv_sym)
    tr = TranslatorDict()
    for (_, code) in TLangs
        tr[Pair(Slang, code)] = deep.mod[deep.provider](source=SLang, target=code)
    end
    tr
end

function translate(str::String, ::srv_val; src::String=SLang, target::String, TR::TranslatorDict)
    # @show "translating string $str"
    @__MODULE__()._translate(str, TR[Pair(src, target)].translate)
end

push!(REG_SERVICES, srv_sym)
