using PyCall
using Gumbo: HTMLElement, HTMLText

const OptPy = Union{PyObject,Nothing}
const TFunc = Union{Function, OptPy}
const StrOrVec = Union{String,Vector{String}}
# stores translate functions for each src/target language pair
const Translator = Dict{Pair{String, String}, TFunc}

@doc """convert a "<script..." string to an `HTMLElement` """
function convert(T::Type{HTMLElement{:script}}, v::String)
    Gumbo.parsehtml(v).root[1][1]
end

@doc "convert string to bytes"
tobytes(str::String)::Vector{UInt8} = Vector{UInt8}(str)

import JSON
# json keys are strings, but we use hashes which are UInt
JSON.convert(T::Type{UInt64}, v::String) = parse(UInt64, v)
