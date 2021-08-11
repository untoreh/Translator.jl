
@doc "Translation library front-end"
module Translator

export translate_dir, translate_file, translate_html, setlangs!

using HTTP: isjson
using Gumbo
using AbstractTrees

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
    if srv ∈ keys(INIT_SERVICES)
        @debug "$srv is already initialized"
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
    INIT_SERVICES[srv] = true
    @debug "Initialized $srv service"
end

function translate_dir(path; service=:deep,
                       inc::IncDict=IncDict())
    @assert isdir(path) "Path $path is not a valid directory"
    srv_sym = Symbol(service)
    srv = Val(srv_sym)
    @assert srv_sym ∈ REG_SERVICES "Specified service $srv_sym not supported"
    dir = dirname(path)
    @assert !isnothing(SLang.code) "Source language not set"
    rx_file = Regex("(.*$(dir)/)(.*\$)")
    # exclude language code denominated directories
    if excluded_translate_dirs === :langs
        exclusions = Set(code for (_, code) in TLangs)
    else
        exclusions = excluded_translate_dirs
    end

    ## translator instances
    TR = init_translator(srv)
    @inline t_fn(txt, target) = translate(txt, srv; src=SLang.code, target=target, TR)
    for file in walkfiles(path;
                          exts=included_translate_exts,
                          dirs=included_translate_dirs,
                          ex_dirs=exclusions)
        @debug "translating: $file"
        # continue
        translate_file(file, rx_file, TLangs, t_fn, inc)
        @debug "translation successful"
    end
end

@doc """ check that a given string is translatable """
const punct_rgx = r"^([[:punct:]]+)|(\s+)$"
function istranslatable(str::AbstractString)
    !isnothing(str) &&
        !isempty(str) &&
        !occursin(punct_rgx, str) &&
        !(isjson(tobytes(str))[1])         # skip json strings
end

# @doc "add element to translation queue if it matches criteria"
# function addelement(el, inc_keys)
# end

txt_getter(el) = el.text
txt_setter(el, val) = el.text = val
alt_getter(el) = el.attributes["alt"]
alt_setter(el, val) = el.attributes["alt"] = val

@doc """traverses a Gumbo HTMLDoc structure translating text nodes and "alt" attributes """
function translate_html(data, path, url_path, lang, t_fn::Function;
                        inc::IncDict=IncDict())

    inc_keys = keys(inc)
    q = Queue(translate=x -> t_fn(x, lang))
    # define element setters
    # use PreOrder to ensure we know if some text belong to a <script> tag
    # collect all the elements that should be translated
    for (_, el) in enumerate(PreOrderDFS(data.root))
        let tp = typeof(el)
            if tp ∈ inc_keys
                push!(el, inc[tp](path, url_path, lang))
            end
            if tp === HTMLText
                # skip scripts
                if typeof(el.parent) ∉ skip_nodes
                    # don't query invalid text for translation
                    if istranslatable(el.text)
                        translate!(q, Node(el, txt_getter, txt_setter))
                    end
                end
            elseif hasfield(tp, :attributes)
                # also translate "alt" attributes which should hold descriptions
                if haskey(el.attributes, "alt")
                    if istranslatable(el.attributes["alt"])
                        translate!(q, Node(el, alt_getter, alt_setter))
                    end
                end
            end
        end
    end
    translate!(q, true)
    data
end

function translate_file(file, rx, languages, t_fn::Function, inc::IncDict)
    let html = read(file, String) |> Gumbo.parsehtml,
        (file_path, url_path) = begin
            m = match(rx, file)
            (String(m[1]), String(m[2]))
        end
        @debug "translating $file"
        for (_, code) in languages
            @debug "lang: $code"
            let t_path = joinpath(file_path, code, url_path),
                d_path = dirname(t_path)
                if !isdir(d_path)
                    mkpath(d_path)
                end
                @debug "writing to path $t_path"
                open(t_path, "w") do io
                    # @show "translating html"
                    translate_html(html, file_path, url_path, code, t_fn; inc) |>
                        x -> print(io, x)
                    # @show "written"
                end
            end
        end
        save_cache()
    end
end

# exportall()
# @exportAll()

end
