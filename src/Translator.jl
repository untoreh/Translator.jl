
@doc "Translation library front-end"
module Translate

using HTTP: isjson

include("misc/env.jl")
include("misc/types.jl")
include("misc/defs.jl")
include("misc/files.jl")
include("misc/cache.jl")
include("services/load.jl")

@doc """setup chosen service and instantiate it.
srv [ :pytrans, :gtrans, :deep, :pytranslators ]
"""
function init(srv = :deep)
    if srv ∈ INITIALIZED_SERVICES
        @warn "$srv is already initialized"
        return
    end
    # NOTE: Conda will install in ~/.local/lib on unix, because conda site-packages is not writeable
    if !ENV_INITIALIZED
        _init_env()
    end
    try
	    init(Val(srv))
    catch
        ErrorException("service $srv not supported") |> throw
    end
    installed[srv] = true
    @warn "Initialized $srv translating service"
end

@doc "returns the cached translation if present, otherwise the return value of the translation function f"
function _translate(str::String, fn::TFunc)
    let k = hash(str)
        if haskey(translated_text, k)
            translated_text[k]
        else
            @show "calling translator service for key $k"
            let trans = fn(str)
                translated_text[k] = isnothing(trans) ? "" : trans
            end
        end
    end
end


function translate_dir(path, service=:deep)
    @assert isdir(path)
    srv_sym = Symbol(service)
    @assert srv_sym ∈ REG_SERVICES
    dir = dirname(path)
    rx_file = r"(.*$(dir)/)(.*$)"
    # exclude language code denominated directories
    if excluded_translate_dirs === :langs
        exclusions = Set(code for (_, code) in TLangs)
    else
        exclusions = excluded_translate_dirs
    end
    
    ## translator instances
    TR = init_translator(Val(srv_sym))
    @inline t_fn(txt, target) = translate(txt, SLang )
    for file in walkfiles(path;
                          exts=included_translate_exts,
                          dirs=included_translate_dirs,
                          ex_dirs=exclusions)
        @warn "translating: $file"
        # continue
        translate_file(file, TLangs; tr=TR)

        sleep(1)
    end
end

@doc """ check that a given string is translatable """
const punct_rgx = r"^[[:punct:]]+$"
function istranslatable(str::String)
    # @show isnothing(match(punct_rgx, str))
    !isnothing(str) &&
        !isempty(str) &&
        isnothing(match(punct_rgx, str)) &&
        !(isjson(tobytes(str))[1])         # skip json strings
end


@doc """traverses a Gumbo HTMLDoc structure translating text nodes and "alt" attributes """
function translate_html(data, path, url_path, lang, t_fn)
    counter = (0, 1000)
    prev_type = Nothing
    script_type = HTMLElement{:script}
    head_type = HTMLElement{:head}
    insert_json = true
    ldj = convert(script_type, LDJ.ldj_trans(path, url_path, lang))
    # use PreOrder to ensure we know if some text belong to a <script> tag
    for (_, el) in enumerate(PreOrderDFS(data.root))
        let tp = typeof(el)
            if insert_json && tp === head_type
                push!(el, ldj)
                insert_json = false
            end
            if tp === HTMLText
                # skip scripts
                if prev_type !== script_type
                    let text_node = el.text
                        # don't query invalid text for translation
                        if istranslatable(text_node)
                            let trans = translate(text_node;
                                                  target=lang,
                                                  TR=TR, service=SERVICE_VAL)
                                # don't replace empty results
                                if !isempty(trans)
                                    el.text = trans
                                end
                            end
                        end
                    end
                end
            elseif hasfield(tp, :attributes)
                # also translate "alt" attributes which should hold descriptions
                if haskey(el.attributes, "alt")
                    let text_node = el.attributes["alt"]
                        if istranslatable(text_node)
                            let trans = translate(text_node; target=lang,
                                                  TR=TR, service=SERVICE_VAL)
                                if !isempty(trans)
                                    el.attributes["alt"] = trans
                                end
                            end
                        end
                    end
                    prev_type  = tp
                end
            end
            counter = Translate.update_translations(counter)
            data
        end
    end
end

const rx_file = r"(.*__site/)(.*$)"
function translate_file(file, languages; tr::Translator)
    let html = read(file, String) |> Gumbo.parsehtml,
        (file_path, url_path) = begin
            m = match(rx_page, file)
            (String(m[1]), String(m[2]))
        end
        # display("translating $file")
        many = 100
        for (_, code) in languages
            display("lang: $code")
            let t_path = joinpath(file_path, code, url_path),
                d_path = dirname(t_path)
                if !isdir(d_path)
                    mkpath(d_path)
                end
                open(t_path, "w") do io
                    # @show "translating html"
                    translate_html(html, file_path, url_path, code, tr) |>
                        x -> print(io, x)
                    # @show "written"
                end
            end
            many -= 1
            if many == 0 return end
        end
        @show "DONE"
    end
end

# exportall()
# @exportAll()

end
