using JSON
using Zarr

const cache_path = joinpath(pwd(), "translations.json")
const cache_path_bak = cache_path * ".bak"
const cache_dict_type = IdDict{UInt64, String}
const translated_text = cache_dict_type()

if length(translated_text) === 0
    if isfile(cache_path)
        try
            merge!(translated_text, JSON.parsefile(cache_path; dicttype=cache_dict_type))
            @warn "loaded translations from $cache_path"
            cp(cache_path, cache_path_bak; force=true)
        catch end
    elseif isfile(cache_path_bak)
        try
            merge!(translated_text, JSON.parsefile(cache_path_bak; dicttype=cache_dict_type))
        catch end
        @warn "loaded translations from $cache_path_bak"
    else
        @assert length(translated_text) === 0
        @warn "no previous translations found at $cache_path"
    end
end

@doc "syncs translations file with in-memory translated text"
function update_translations(counter::Tuple{Int, Int})
    if !iszero(counter[1]) && iszero(counter[1] % counter[2])
        @warn "updating translations"
        open(cache_path, "w") do f
            JSON.print(f, translated_text)
        end
        (0, counter[2])
    else
        (counter[1]+1, counter[2])
    end
end
