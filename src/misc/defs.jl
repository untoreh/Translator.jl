include("tokens.jl")

using BitConverter: bytes
import Base.push!
using Gumbo: HTMLElement

const included_translate_dirs = Set(("posts", "tag", "reads", "_rss"))
const excluded_translate_dirs = Set{Union{Symbol, String}}()
const included_translate_exts = Set((".md", ".html"))
const skip_nodes = Set(
    HTMLElement{sym} for sym in [:code, :style, :script, :address, :applet, :audio, :canvas, :embed, :time, :video]
        )
const skip_class = Set(("menu-lang-btn", ))
# Every element is a function that applies modifications
# an el of HTMLElement
# Function signature: (el::HTMLElement, file_path::String, url_path::String, pair::LangPair)
tforms = Dict{Type, Function}()

const REG_SERVICES = Vector{Symbol}(undef, 0)
const INIT_SERVICES = Dict{Symbol, Bool}()

hostname = nothing

@kwdef mutable struct Lang
    lang::Union{Nothing, String} = nothing
    code::Union{Nothing, String} = nothing
end

const SLang = Lang()

const TLangs = Vector{Lang}(undef, 0)

@doc """
sets the source and target languages global vars for translation
"""
function setlangs!(source::Lang, targets::AbstractVector{Lang})
    global SLang, TLangs
    (SLang.lang, SLang.code) = source.lang, source.code
    empty!(TLangs)
    append!(TLangs, targets)
end

TuPair = Union{Pair{String, String}, Tuple{String, String}}
function setlangs!(source::T,
                   targets::AbstractVector{T}) where T <: TuPair
    let src_lang = Lang(source[1], source[2]),
        trg_langs = [Lang(tlang[1], tlang[2]) for tlang in targets
                         if tlang[2] != src_lang.code]
        setlangs!(src_lang, trg_langs)
    end
end

function sethostname!(host)
    global hostname
    u = URI(host)
    hostname = isempty(u.host) ? u.path : u.host
end

function get_queue(f, pair, TR::TranslatorService,  ::Any...)
    GlueQueue(translate=f, pair=pair, TR=TR)
end

function _update_elements!(q::GlueQueue)
    query = join((get_text(el) for el in q.bucket), q.glue)
    @debug "querying translation function, " *
        "bucket: $(length(q.bucket)), query: $(length(query))"
    trans = q.translate(query) |> x -> split(x, q.splitGlue)
    _check_batched_translation(q, query, trans)
    for (el, t) in zip(q.bucket, trans)
        _set_el(q, el, t)
        # end
    end
    empty!(q.bucket)
    q.sz[] = 0
end


function _set_from_cache(pair, el)
    txt = get_text(el)
    k = hash((pair, txt))
    len = length(txt)
    if k ∈ tr_cache_dict
        set_text(el, tr_cache_dict[k])
        (true, len)
    elseif k ∈ tr_cache_tmp
        set_text(el, tr_cache_tmp[k])
        (true, len)
    else
        (false, len)
    end
end

function _set_from_db(pair, el)
    txt = get_text(el)
    k = hash((pair.src, pair.trg, txt))
    len = length(txt)
    if haskey(tr_cache_tmp, k)
        set_text(el, tr_cache_tmp[k])
        (true, len)
    else
        bk = bytes(k)
        if bk ∈ db.db
            set_text(el, view(db.db, bk))
            (true, len)
        else
            (false, len)
        end
    end
end

function translate!(q::GlueQueue, el::HTMLNode, srv::Val, ::Any...)
    let (success, len) = _set_from_db(q.pair, el)
        if !success
            # translate nodes that exceede bufsize singularly
            if len > q.bufsize
                _update_el!(q, el, srv)
            else
                if q.sz[] + len > q.bufsize
                    # @assert length(q.bucket) > 0
                    _update_elements!(q)
                    save_to_db()
                end
                push!(q.bucket, el)
                q.sz[] += len
            end
        end
    end
end

function translate!(q::GlueQueue, ::Val=Val(nothing); finish::Bool)
    if finish && q.sz[] > 0
        _update_elements!(q)
    end
end

@doc "force translation, ignoring bufsize"
function translate!(q::Queue, el::HTMLNode, ::Val=Val(nothing); finish::Bool)
    if finish
        let (success, _) = _set_from_db(q.pair, el)
            if !success
                let txt = get_text(el),
                    t = q.translate(txt)
                    # @show t
                    set_text(el, t)
                    tr_cache_tmp[hash((q.pair, txt))] = t
                end
            end
        end
    end
end

abstract type HTMLElementAttr end

get_text(el::HTMLText) = el.text
set_text(el::HTMLText, val) = el.text = val

get_text(el::HTMLElement) = if haskey(el.attributes, "alt")
    el.attributes["alt"] else
    el.attributes["title"]
end
set_text(el::HTMLElement, val) = el.attributes[
    haskey(el.attributes, "alt") ? "alt" : "title"
] = val

const RTL_LANGS = Set(["yi",
                       "he",
                       "ar",
                       "fa",
                       "ur",
                       "az",
                       "dv",])
