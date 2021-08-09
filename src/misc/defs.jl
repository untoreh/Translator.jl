using Base: @kwdef, @NamedTuple
import Base.push!
using Gumbo: HTMLElement

const included_translate_dirs = Set(("posts", "tag", "reads", "_rss"))
const excluded_translate_dirs = Set{String}()
const included_translate_exts = Set((".md", ".html"))
const skip_nodes = Set([HTMLElement{:script}, HTMLElement{:style}])


const REG_SERVICES = Vector{Symbol}(undef, 0)
const INIT_SERVICES = Dict{Symbol, Bool}()

@kwdef mutable struct LangPair
    lang::Union{Nothing, String} = nothing
    code::Union{Nothing, String} = nothing
end

const SLang = LangPair()

const TLangs = Vector{TuPair}(undef, 0)

@doc """
sets the source and target languages global vars for translation
"""
function setlangs!(source::T, targets::AbstractVector{T}) where T <: TuPair
    global SLang, TLangs
    if !(typeof(source) <: TuPair) || !(typeof(first(targets)) <: TuPair)
        throw("wrong language structure")
    end
    (SLang.lang, SLang.code) = source
    empty!(TLangs)
    let (_, sc) = source
        for (lang, code) in targets
            if code !== sc
                push!(TLangs, Pair(lang, code))
            end
        end
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
    glue = " ;*;#;&;*; "
    splitGlue = r"\s?;\*;#;&;\*;\s?"
    buffer = 2000
    translate::Function
end

function translate!(q::Queue, node::Node)
    len = length(node.get(node.el))
    if q.sz[] + len > q.buffer && length(q.bucket) > 0
        push!(q.bucket, node)
        query = join((n.get(n.el) for n in q.bucket), q.glue)
        trans = q.translate(query) |> x -> split(x, q.splitGlue)
        if length(trans) !== length(q.bucket)
            @error "mismatching batched translation query result"
        else
            for (n, t) in zip(q.bucket, trans)
                n.set(n.el, t)
                @show n.get(n.el)
            end
        end
        empty!(q.bucket)
    else
        q.sz[] += len
        push!(q.bucket, node)
    end
    q
end
