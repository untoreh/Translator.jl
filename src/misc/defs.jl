const included_translate_dirs = Set(("posts", "tag", "reads", "_rss"))
const excluded_translate_dirs = Set()
const included_translate_exts = Set((".md", ".html"))

const REG_SERVICES = Vector{Symbol}(undef, 0)
const INIT_SERVICES = Dict{Symbol, Bool}()
Base.@kwdef mutable struct LangPair
    lang::Union{Nothing, String} = nothing
    code::Union{Nothing, String} = nothing
end
const SLang = LangPair()

const TLangs = Vector{Pair{String, String}}(undef, 0)

function addtlangs(langs::AbstractVector)
    t = typeof(first(langs))
    if t ∉ [Tuple{String, String}, Pair{String, String}]
        throw("wrong language structure")
    end
    empty!(TLangs)
    for (lang, code) in langs
        push!(Pair(lang, code), TLangs)
    end
end
