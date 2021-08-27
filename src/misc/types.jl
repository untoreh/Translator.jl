using PyCall
using Gumbo: HTMLElement, HTMLText
using Base: @NamedTuple, @kwdef

const OptPy = Union{PyObject,Nothing}
const TFunc = Union{Function, OptPy}
const StrOrVec = Union{String,Vector{String}}
const HTMLNode = Union{HTMLText, HTMLElement}

const LangPair = @NamedTuple {src::String, trg::String}

# stores translate functions for each src/target language pair
const TranslatorDict = Dict{LangPair, TFunc}
const TranslatorService = Tuple{Val, TranslatorDict}

@doc """convert a "<script..." string to an `HTMLElement` """
function convert(T::Type{HTMLElement{:script}}, v::String)
    Gumbo.parsehtml(v).root[1][1]
end

@doc "convert string to bytes"
tobytes(str::Union{SubString, String})::Vector{UInt8} = Vector{UInt8}(str)

import JSON
# json keys are strings, but we use hashes which are UInt
JSON.convert(T::Type{UInt64}, v::String) = parse(UInt64, v)

abstract type Queue end

@kwdef struct GlueQueue <: Queue
    sz = Ref{Int}(0)
    bucket::Vector = []
    glue = " \n[[...]]\n "
    splitGlue = r"\s?\n?\[\[\.\.\.\]\]\n?"
    bufsize = 1600
    translate::Function
    pair::LangPair
    TR::TranslatorService
end
