using PyCall
using MacroTools
using Conda

function isunset(sym::Symbol, field::Union{Nothing, Symbol}=nothing)
    ! isdefined(@__MODULE__, sym) ||
        isnothing(getfield(@__MODULE__, sym) |>
        (x) -> (isnothing(field) ? x : getfield(x, field)))
end

# function combinearg(sym, type, slurp, def)
#     if isnothing(def)
#         if slurp
#             :($sym::$type...)
#         else
#             :($sym::$type)
#         end
#     else
#         if slurp
#             :($sym::$type...=$def)
#         else
#             :($sym::$type=$def)
#         end
#     end
# end

function replace_args(args::Vector{Any})
    out = similar(args)
    for (n, a) in enumerate(map(splitarg, args))
        if !isa(a[2], Expr)
            out[n] = MacroTools.combinearg(
                a[1],
                getfield(@__MODULE__, a[2]),
                a[3],
                a[4])
        else
            out[n] = args[n]
        end
    end
    out
end


macro typesderef(expr)
    let q = quote
        $(begin
              df = splitdef(expr)
              t_args = Vector{Expr}()
              df[:args] = replace_args(df[:args])
              # slurping only at the end allow on julia 1.7
              df[:kwargs] = replace_args(df[:kwargs])
              ed = length(df[:kwargs]) > 0 ? df[:kwargs][end] : nothing
              if ed isa Expr && @capture(ed, a_::T_...)
                  # Slurping shouldn't have type hints
                  # and apparently even if there aren't
                  # an `Any` type gets added automatically
                  # which should be ignored
                  df[:kwargs][end] = :($a...)
              end
              combinedef(df)
          end)
    end
        eval(q)
    end
end
