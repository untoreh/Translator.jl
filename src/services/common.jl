using PyCall
using Conda

const INITIALIZED_SERVICES = Dict{Symbol, Bool}()

function isunset(sym::Symbol, field::Union{Nothing, Symbol}=nothing)
    ! isdefined(@__MODULE__, sym) ||
        isnothing(getfield(@__MODULE__, sym) |>
        (x) -> (isnothing(field) ? x : getfield(x, field)))
end
