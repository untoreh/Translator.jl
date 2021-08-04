mutable struct GoogleTrans
    mod::OptPy
    tr::OptPy
end

srv_sym = :googletrans
srv_val = Val{srv_sym}


if isunset(srv_sym)
    const googletrans =  GoogleTrans(nothing, nothing)
end

function init(::srv_val)
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

function init_translator(SLang, TLangs, ::srv_val)
    init(srv_sym)
    tr = Translator()
    for (_, code) in TLangs
        tr[Pair(Slang, code)] = googletrans.tr.translate
    end
end

function translate(str::StrOrVec, ::srv_val; src=SLang, target::String, TR::Translator)
    let t_fn(x) = TR[Pair(SLang, target)](x, src = src, dest = target).text
        @__MODULE__()._translate(str, t_fn)
    end
end

push!(REG_SERVICES, srv_sym)