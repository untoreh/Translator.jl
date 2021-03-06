mutable struct Argos
    mod::OptPy
    pkg::OptPy
    trans::OptPy
    tags::OptPy
    Tag::OptPy
    translate_tags::OptPy
    tr::Dict{Symbol, OptPy}
end

srv_sym = :argos
srv_val = Val{srv_sym}
ArgosTranslator = Tuple{srv_val, TranslatorDict}

if isunset(srv_sym, :mod)
    const argos = Argos(nothing, nothing, nothing, nothing, nothing, nothing, Dict())
end


function argos_download_models()
    if isnothing(argos.pkg)
        init(Val(:argos))
    end
    argos.pkg.update_package_index()
    inst = argos.pkg.get_installed_packages()
    installed = Set([(i.from_code, i.to_code) for i in inst])
    for p in argos.pkg.get_available_packages()
        if (p.from_code, p.to_code) ∈ installed
            continue
        end
        display("downloading model: $(p.get_description())")
        path = p.download()
        argos.pkg.install_from_path(path)
        display("installed.")
    end
end

@typesderef function init(::srv_val)
    let f() = begin
        argos.mod = pyimport("argostranslate")
        argos.trans = pyimport("argostranslate.translate")
        argos.pkg = pyimport("argostranslate.package")
        argos.tags = pyimport("argostranslate.tags")
        argos.Tag = argos.tags.Tag
        argos.translate_tags = argos.tags.translate_tags
    end
        try
            f()
        catch
            Conda.pip("install", "argostranslate")
            f()
        end
    end
    argos_download_models()
end

function argos_source_language(source)
    for ilang in argos.trans.get_installed_languages()
        if ilang.code === source
            return ilang
        end
    end
end

@typesderef function init_translator(srv::srv_val; targets=TLangs, source=SLang.code)
	init(srv)
    argos.trans.load_installed_languages()
    s_ilang = argos_source_language(source)
    tr = TranslatorDict()
    for lang_obj in s_ilang.translations_from
        let tlang = lang_obj.to_lang.code
            tr[(src=source, trg=tlang)] = lang_obj
        end
    end
    (srv, tr)
end

@typesderef function get_tfun(lang::LangPair, TR::ArgosTranslator)
    # @show "translating string $str"
    TR[2][lang].translate
end

@kwdef struct ArgosQueue <: Queue
    q::GlueQueue
end

function translate!(q::GlueQueue, el::HTMLNode, srv::Val{:argos})
    translate!(q, el, srv; finish=true)
end

function translate!(q::GlueQueue, ::Val{:argos}; finish=false)
    translate!(q; finish)
end

push!(REG_SERVICES, srv_sym)
