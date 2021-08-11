using JSON
using CodecZstd
using Serialization: serialize, deserialize
using TranscodingStreams

const tr_cache_path = joinpath(pwd(), "translations.zst")
const tr_cache_path_bak = tr_cache_path * ".bak"
# const cache_dict_type = IdDict{UInt64, String}
const cache_dict_type = IdDict{UInt64, String}
const tr_cache_disk_length = Ref(0)
const tr_cache_dict = cache_dict_type()
const tr_cache_tmp = cache_dict_type()
@doc "how many translated keys can disk cache be out of sync"
const tr_cache_max_diff = 200
const tr_cache_buf = IOBuffer() # not thread safe
const tr_cache_cstream = ZstdCompressorStream(tr_cache_buf)
const zstdcomp = ZstdCompressor()
const TOKEN_END = TranscodingStreams.TOKEN_END
const MAX_CACHE_SIZE = 536870912
TranscodingStreams.initialize(zstdcomp)

load_cache(s::String) = load_cache([s])

function load_cache(files=[tr_cache_path, tr_cache_path_bak])
    if length(files) === 0
        @error "no more files available for cache loading"
        return
    end
    file_path = popfirst!(files)
    name, ext = splitext(file_path)
    ext2 = splitext(name)[2]
    if isfile(file_path)
        try
            if ext === ".json" || ext2 === ".json"
                merge!(tr_cache_dict,
                       JSON.parsefile(file_path, dicttype=cache_dict_type))
            elseif ext === ".zst" || ext2 === ".zst"
                open(file_path, "r") do f
                    let stream = ZstdDecompressorStream(f)
                        merge!(tr_cache_dict,
                               deserialize(stream))
                        close(stream)
                    end
                end
            end
            save_cache(tr_cache_path_bak; force=true)
            @debug "loaded translations from $file_path, keys: $(tr_cache_disk_length)"
        catch
            load_cache(files)
        end
    end
end

@doc "syncs translations file with in-memory translated text"
function save_cache(file_path=tr_cache_path; force=false, nojson=false)
    if length(tr_cache_tmp) > tr_cache_max_diff || force
        @debug "saving $(length(tr_cache_tmp)) translations"
        merge!(tr_cache_dict, tr_cache_tmp)
        empty!(tr_cache_tmp)
        if nojson
	        remove_json()
        end
        open(file_path, "w") do f
            @debug "serializing tr dict, length: $(length(tr_cache_dict))"
            serialize(tr_cache_cstream, tr_cache_dict)
            write(tr_cache_cstream, TOKEN_END)
            flush(tr_cache_cstream)
            @debug "writing to file: $f"
            write(f, take!(tr_cache_buf))
        end
        tr_cache_disk_length[] = length(tr_cache_dict)
    end
end

function remove_json(dict=tr_cache_dict)
	for (k, v) in dict
        if isjson(tobytes(v))[1]
            delete!(dict, k)
        end
    end
end
