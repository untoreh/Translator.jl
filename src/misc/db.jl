using LevelDB
using StringViews
using BitConverter: bytes

const tr_db_path = "translations.db"
const empty_vec = Vector{UInt8}()
mutable struct TDB
    db::Union{Nothing, LevelDB.DB}
end
const db = TDB(nothing)


Base.setindex!(db::LevelDB.DB, v::String, k::String...) = db[k] = v
Base.setindex!(db::LevelDB.DB, v::String, k::Int...) = db[k] = v

function Base.length(db::LevelDB.DB)
    length(keys(db))
end

function Base.size(db::LevelDB.DB)
    sum([length(v) for v in values(db, Vector{UInt8})])
end

function Base.setindex!(db::LevelDB.DB, v::String, k::AbstractSet{Int})
    let av = Vector{UInt8}(v)
        db[[bytes(ki) for ki in k]] = [av for _ in 1:length(k)]
    end
end

function Base.setindex!(db::LevelDB.DB, v::Any, k::AbstractSet)
    db[[bytes(ki) for ki in k]] = [Vector{UInt8}(vi) for vi in v]
end

function Base.setindex!(db::LevelDB.DB, v::String, k::Vector{String})
    let av = Vector{UInt8}(v)
        db[[Vector{UInt8}(ki) for ki in k]] = [av for _ in 1:length(k)]
    end
end

function Base.setindex!(db::LevelDB.DB, v::Vector{UInt8}, k::Vector{Vector{UInt8}})
    db[k] = [Vector{UInt8}(v) for _ in 1:length(k)]
end

function Base.keys(db::LevelDB.DB, T::Type=StringView)
    if applicable(convert, T, empty_vec)
        [convert(T, i[1]) for i in db if typeof(i) !== LevelDB.Iterator]
    else
        [T(i[1]) for i in db if typeof(i) !== LevelDB.Iterator]
    end
end

function Base.values(db::LevelDB.DB, T::Type=StringView)
    if applicable(convert, T, empty_vec)
        [convert(T, t[2]) for t in db if typeof(t) !== LevelDB.Iterator]
    else
        [T(t[2]) for t in db if typeof(t) !== LevelDB.Iterator]
    end
end

Base.empty!(db::LevelDB.DB) = delete!(db, keys(db, Vector{UInt8}))

function load_db(path=tr_db_path)
    if typeof(db.db) !== LevelDB.DB
        db.db = LevelDB.DB(path; create_if_missing = true, error_if_exists = false)
        atexit( () -> close(db.db) )
    end
end

function save_to_db(db=db.db; force=false, nojson=false)
    if length(tr_cache_tmp) > tr_cache_max_diff || force
        @debug "saving $(length(tr_cache_tmp)) translations"
        if nojson
            remove_json(tr_cache_tmp)
        end
        db[keys(tr_cache_tmp)] = values(tr_cache_tmp)
    end
end
