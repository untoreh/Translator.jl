using Base: @kwdef
using BitConverter: bytes
import Base.push!
using Gumbo: HTMLElement

const included_translate_dirs = Set(("posts", "tag", "reads", "_rss"))
const excluded_translate_dirs = Set{String}()
const included_translate_exts = Set((".md", ".html"))
const skip_nodes = Set([HTMLElement{:script}, HTMLElement{:style}, HTMLElement{:code},
                        HTMLElement{:link}])


const REG_SERVICES = Vector{Symbol}(undef, 0)
const INIT_SERVICES = Dict{Symbol, Bool}()

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

struct Node
    el::Any
    get::Function
    set::Function
end

@kwdef struct Queue
    sz = Ref{Int}(0)
    # element, getter and setter
    bucket::Vector{Node} = []
    glue = " \n[[...]]\n "
    splitGlue = r"\s?\n?\[\[\.\.\.\]\]\n?"

    buffer = 1600
    translate::Function
    pair::LangPair
end

function _update_elements(q::Queue)
    query = join((n.get(n.el) for n in q.bucket), q.glue)
    @debug "querying translation function, " *
        "bucket: $(length(q.bucket)), query: $(length(query))"
    trans = q.translate(query) |> x -> split(x, q.splitGlue)
    if length(trans) !== length(q.bucket)
        display(query)
        for t in trans display(t) end
        throw(("mismatching batched translation query result: " *
            "$(length(trans)) - $(length(q.bucket)) "))
    else
        for (n, t) in zip(q.bucket, trans)

            tr_cache_tmp[hash((q.pair, n.get(n.el)))] = t
            n.set(n.el, t)
            # end
        end
    end
    empty!(q.bucket)
    q.sz[] = 0
end


function _set_from_cache(pair, node)
    txt = node.get(node.el)
    k = hash((pair, txt))
    len = length(txt)
    if k ∈ tr_cache_dict
        node.set(node.el, tr_cache_dict[k])
        (true, len)
    elseif k ∈ tr_cache_tmp
        node.set(node.el, tr_cache_tmp[k])
        (true, len)
    else
        (false, len)
    end
end

function _set_from_db(pair, node)
    txt = node.get(node.el)
    k = hash((pair, txt))
    len = length(txt)
    if haskey(tr_cache_tmp, k)
        node.set(node.el, tr_cache_tmp[k])
        (true, len)
    else
        bk = bytes(k)
        if in(bk, db.db)
            node.set(node.el, db.db[bk])
            (true, len)
        else
            (false, len)
        end
    end
end

function translate!(q::Queue, node::Node, ::Val...)
    let (success, len) = _set_from_db(q.pair, node)
        if !success
            if q.sz[] + len > q.buffer && length(q.bucket) > 0
                push!(q.bucket, node)
                _update_elements(q)
                save_to_db()
            else
                q.sz[] += len
                push!(q.bucket, node)
            end
        end
    end
end

function translate!(q::Queue, finish::Bool)
    if finish && q.sz[] > 0
        _update_elements(q)
    end
end

function translate!(q::Queue, node::Node, finish::Bool)
    if finish
        let (success, len) = _set_from_db(q.pair, node)
            if !success
                let txt = node.get(node.el),
                    t = q.translate(txt)
                    @show t
                    node.set(node.el, t)
                    tr_cache_tmp[hash((q.pair, txt))] = t
                end
            end
        end
    end
end

function translate!(q, node, ::Val{:argos})
    translate!(a, node, true)
end
