
@doc "Translation library front-end"
module Translator

export translate_dir, translate_file, translate_html, setlangs!, sethostname!, trav_files, trav_langs

using Memoization
using Memoization: empty_cache!
using HTTP: isjson
using URIs: URI
using Gumbo
using AbstractTrees

include("misc/env.jl")
include("misc/types.jl")
include("misc/defs.jl")
include("misc/files.jl")
include("misc/cache.jl")
include("misc/db.jl")
include("services/load.jl")

@doc """Setup chosen service and instantiate it.
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

function link_src_to_dir(dir)
    let link_path = joinpath(dir, SLang.code)
        if ispath(link_path) && !islink(SLang.code)
                @warn "removing non link path: $link_path"
                rm(link_path)
        end
        symlink("./", link_path)
        @debug "symlinked $dir to $link_path"
    end
end

@enum traverse_method trav_files=1 trav_langs=2

function translate_dir(path; service=:deep, method::traverse_method=files, clear=true)
    @assert isdir(path) "Path $path is not a valid directory"
    srv_sym = Symbol(service)
    srv = Val(srv_sym)
    @assert srv_sym ∈ REG_SERVICES "Specified service $srv_sym not supported"
    dir = isdirpath(path) ? dirname(path) : path
    @assert !isnothing(SLang.code) "Source language not set"
    rx_file = Regex("(.*$(dir)/)(.*\$)")
    # exclude language code denominated directories
    if length(excluded_translate_dirs) > 0 &&
        first(excluded_translate_dirs) === :langs
        exclusions = Set(lang.code for lang in TLangs)
    else
        exclusions = excluded_translate_dirs
    end
    ## translator instances
    TR = init_translator(srv)
    langpairs = [(src=SLang.code, trg=lang.code) for lang in TLangs]
    link_src_to_dir(path)

    clear && empty_cache!(parse_html)
    if method == trav_files
        _file_wise(path; exclusions, rx_file, langpairs, TR)
    elseif method == trav_langs
        _lang_wise(path; exclusions, rx_file, langpairs, TR)
    end

    Translator.save_to_db(;force=true)
end

function write_files(trees)
    for (file, tree) in trees
        open(file, "w") do f
	        print(f, tree)
        end
        delete!(trees, file)
    end
end

function _lang_wise(path; exclusions, rx_file, langpairs, TR)
    trees = Dict{String, HTMLDocument}()
    prev_bucket_len = 0
    q = nothing
    for pair in langpairs
        @debug "lang wise translation for $pair"
        for file in walkfiles(path;
                              exts=included_translate_exts,
                              dirs=included_translate_dirs,
                              ex_dirs=exclusions)
            (t_path, (q, out)) = parse_file(file, rx_file, pair, TR, q)
            # if the queue was flushed, previous files should be fully translated
            # so we can write them to storage and remove them
            let new_bucket_len = length(q.bucket)
                if new_bucket_len < prev_bucket_len
                    write_files(trees)
                end
                prev_bucket_len = new_bucket_len
            end
            trees[t_path] = out
        end
        # finish remaining translations for pair
        translate!(q, TR[1]; finish=true)
        write_files(trees)
        q = nothing
    end
end

function _file_wise(path; exclusions, rx_file, langpairs, TR)
    for file in walkfiles(path;
                          exts=included_translate_exts,
                          dirs=included_translate_dirs,
                          ex_dirs=exclusions)
        @debug "translating: $file"
        # continue
        translate_file(file, rx_file, langpairs, TR)
        @debug "translation successful"
    end
end

@doc """Check that a given string is translatable."""
const punct_rgx = r"^([[:punct:]]|\s)+$"

function istranslatable(str::AbstractString)
    !isnothing(str) &&
        !isempty(str) &&
        !occursin(punct_rgx, str) &&
        !(isjson(tobytes(str))[1])         # skip json strings
end

@doc "Rewrite urls that match a particular hostname, prepending target lang to url path."
function rewrite_url(el, rewrite_path, hostname)
    let u = URI(getattr(el, "href")),
        # remove initial dots from links
        p = replace(u.path, r"\.?\.?" => "")
        if (isempty(u.host) || hostname === u.host) &&
            startswith(p, "/") # don't rewrite local #id links
            join([rewrite_path, p]) |>
                x -> URI(u; path=x) |> string |>
                x -> setattr!(el, "href", x)
        end
    end
end

@doc """Check that a link doesn't have classes belonging to skip_class."""
function in_skip_class(tp, el)
    hasfield(tp, :attributes) &&
        haskey(el.attributes, "class") &&
        any(occursin(c, el.attributes["class"]) for c in skip_class)
end

@doc """Traverses a Gumbo HTMLDoc structure translating text nodes and "alt" attributes."""
function translate_html(data, file_path, url_path, pair::LangPair, TR::TranslatorService;
                        q::Union{Nothing, Queue}=nothing, hostname=hostname, finish=true)

    tform_els = keys(tforms)
    rewrite_path = "/" * pair.trg

    srv = TR[1]
    out_tree = deepcopy(data)
    if isnothing(q)
        q = get_tfun(pair, TR) |> f -> get_queue(f, pair, TR)
    end

    skip_children = 0

    # Set the target lang attribute at the top level
    setattr!(out_tree.root, "lang", pair.trg)
    # and the RTL tag
    if pair.trg ∈ RTL_LANGS
        setattr!(out_tree.root, "dir", "rtl")
    end

    # If using :argos translation service, don't use bulk translation.
    # Use PreOrder to ensure we know if some text belong to a <script> tag.
    # Prefetch the elements (collect) since we are going to modify the tree inplace,
    # which would change the running loop iteration order.
    for el in PreOrderDFS(out_tree.root)
        tp = typeof(el)
        # apply modifications
        if tp ∈ tform_els
            tforms[tp](el, file_path, url_path, pair)
        end
        # check first if we are skipping children of a previous skipped node
        if skip_children > 0
            skip_children += - 1 + (hasfield(tp, :children) ? length(el.children) : 0)
            continue
        # skip unwanted nodes and their children
        elseif tp ∈ skip_nodes || in_skip_class(tp, el)
            skip_children = length(el.children)
            continue
        end
        if tp === HTMLText
            # don't query invalid text for translation
            if istranslatable(el.text)
                translate!(q, el, srv)
            end
        elseif tp == HTMLElement{:a}
            # append translated /lang/ path to local URLs
            if haskey(el.attributes, "href")
                rewrite_url(el, rewrite_path, hostname)
            end
        elseif hasfield(tp, :attributes)
            # also translate "alt" attributes which should hold descriptions
            if haskey(el.attributes, "alt")
                if istranslatable(el.attributes["alt"])
                    translate!(q, el, srv)
                end
            elseif haskey(el.attributes, "title")
                if istranslatable(el.attributes["title"])
                    translate!(q, el, srv)
                end
            end
        end
    end
    translate!(q, srv; finish=finish)
    (q, out_tree)
end

function translate_file(file, rx, langpairs::Vector{LangPair}, TR::TranslatorService; t_path=nothing)
    let html = parse_html(file),
        (file_path, url_path) = split_file_path(rx, file)
        @debug "translating $file"
        for pair in langpairs
            @debug "lang: $(pair.trg)"
            let t_path = isnothing(t_path) ? joinpath(file_path, pair.trg, url_path) : t_path,
                d_path = dirname(t_path)
                if !isdir(d_path)
                    mkpath(d_path)
                end
                @debug "writing to path $t_path"
                open(t_path, "w") do io
                    # @show "translating html"
                    translate_html(html, file_path, url_path, pair, TR) |>
                        q_out -> print(io, q_out[2])
                    # @show "written"
                end
            end
        end
    end
end

function split_file_path(rx, file)
    m = match(rx, file)
    (String(m[1]), String(m[2]))
end

@memoize parse_html(file) = read(file, String) |> Gumbo.parsehtml

function parse_file(file, rx, pair::LangPair, TR::TranslatorService, q::Union{Queue, Nothing}=nothing)
    html = parse_html(file)
    (file_path, url_path) = split_file_path(rx, file)
    @debug "collecting elements for $file"
    let t_path = joinpath(file_path, pair.trg, url_path),
        d_path = dirname(t_path)
        if !isdir(d_path)
            mkpath(d_path)
        end
        (t_path,
        translate_html(html, file_path, url_path, pair, TR; q, finish=false))
    end
end

@doc "Code loading helper function for translating a franklin project"
function franklinlangs()
    include(joinpath(dirname(@__FILE__), "misc/franklin.jl"))
    @eval export FranklinLangs
end

end
