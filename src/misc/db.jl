using LevelDB
using LevelDB: DB, @check_err_ref, leveldb_get, Csize_t
using StringViews
using BitConverter: bytes, to_int, to_big
import Base.convert, Base.setindex!

const tr_db_path = "translations.db"
const empty_vec = Vector{UInt8}()
mutable struct TDB
    db::Union{Nothing, LevelDB.DB}
end
const db = TDB(nothing)

setindex!(db::LevelDB.DB, v::String, k::Int) = db[k] = v
convert(::Type{<:Int}, v::Vector{UInt8}) = to_int(v)
convert(::Type{<:UInt}, v::Vector{UInt8}) = UInt(to_big(v))
convert(::Type{UInt64}, v::Vector{UInt8}) = UInt(to_big(v))

function Base.length(db::LevelDB.DB)
    length([k for k in keys(db)])
end

function Base.in(k::AbstractString, db::LevelDB.DB)
    Vector{UInt8}(k) ∈ db
end

function Base.in(k::Number, db::LevelDB.DB)
    bytes(k) ∈ db
end

function Base.in(k::Vector{UInt8}, db::LevelDB.DB)
    val_size = Ref{Csize_t}(0)
    @check_err_ref leveldb_get(db.handle, db.read_options,
                               pointer(k), length(k),
                               val_size, err_ref)
    size = val_size[]
    size != 0
end

function Base.size(db::LevelDB.DB)
    sum([length(v) for v in values(db, Vector{UInt8})])
end

function setindex!(db::LevelDB.DB, v::String, k::String)
    db[Vector{UInt8}(k)] = Vector{UInt8}(v)
end

function Base.getindex(db::LevelDB.DB, k::String)
    StringView(db[Vector{UInt8}(k)])
end

function Base.view(db::LevelDB.DB, k::Vector{UInt8})
    StringView(db[k])
end

function setindex!(db::LevelDB.DB, v::String, k::AbstractSet{Int})
    let av = Vector{UInt8}(v)
        db[[bytes(ki) for ki in k]] = [av for _ in 1:length(k)]
    end
end

function setindex!(db::LevelDB.DB, v::Any, k::AbstractSet)
    db[[bytes(ki) for ki in k]] = [Vector{UInt8}(vi) for vi in v]
end

function setindex!(db::LevelDB.DB, v::String, k::Vector{String})
    let av = Vector{UInt8}(v)
        db[[Vector{UInt8}(ki) for ki in k]] = [av for _ in 1:length(k)]
    end
end

function setindex!(db::LevelDB.DB, v::Vector{UInt8}, k::Vector{Vector{UInt8}})
    db[k] = [Vector{UInt8}(v) for _ in 1:length(k)]
end

function Base.keys(db::LevelDB.DB, T::Union{Type, Function}=StringView)
    if applicable(convert, T, empty_vec)
        (convert(T, i[1]) for i in db if typeof(i) !== LevelDB.Iterator)
    else
        (T(i[1]) for i in db if typeof(i) !== LevelDB.Iterator)
    end
end

function Base.values(db::LevelDB.DB, T::Type=StringView)
    if applicable(convert, T, empty_vec)
        (convert(T, t[2]) for t in db if typeof(t) !== LevelDB.Iterator)
    else
        (T(t[2]) for t in db if typeof(t) !== LevelDB.Iterator)
    end
end

Base.delete!(db::LevelDB.DB, s::AbstractString) = delete!(db, Vector{UInt8}(s))
Base.empty!(db::LevelDB.DB) = delete!(db, keys(db, Vector{UInt8}))

function load_db(path=tr_db_path)
    if typeof(db.db) !== LevelDB.DB
        db.db = LevelDB.DB(path; create_if_missing = true, error_if_exists = false)
        atexit( () -> close(db.db) )
    end
    db.db
end

function save_to_db(db::LevelDB.DB=db.db; force=false, nojson=false)
    if length(tr_cache_tmp) > tr_cache_max_diff || force
        @debug "saving $(length(tr_cache_tmp)) translations"
        if nojson
            remove_json(tr_cache_tmp)
        end
        db[keys(tr_cache_tmp)] = values(tr_cache_tmp)
    end
end

function reset_db()
	empty!(tr_cache_tmp)
    close(db.db)
    db.db = nothing
    load_db()
end

function clear_db()
    empty!(db.db)
    empty!(tr_cache_tmp)
end
