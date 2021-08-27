using WordTokenizers: split_sentences

const sentence_vec = Vector{String}()
const trans_vec = Vector{String}()

@inline function _set_el(q, el, trans)
    tr_cache_tmp[hash((q.pair.src, q.pair.trg, get_text(el)))] = trans
    set_text(el, trans)
end

function _check_batched_translation(q, query, trans)
    if length(trans) !== length(q.bucket)
        display(query)
        for t in trans display(t) end
        throw(("mismatching batched translation query result: " *
            "$(length(trans)) - $(length(q.bucket)) "))
    end
end

function _do_trans(q)
    query = join(sentence_vec, q.glue)
    trans = q.translate(query) |> x -> split(x, q.splitGlue)
    _check_batched_translation(q, query, trans)
    append!(trans_vec, trans)
    empty!(sentence_vec)
end

function _update_el!(q::Queue, el::HTMLNode, ::Val)
    if split
        len = 0
	    sents = split_sentences(get_text(el))
        for s in sents
            len += length(s)
            if len > q.bufsize
                @assert length(sentence_vec) > 0
                _do_trans(q)
            end
            push!(sentence_vec, s)
        end
        # finalize
        _do_trans(q)
        _set_el(q, el, join(trans_vec))
        empty!(trans_vec)
    end
end
