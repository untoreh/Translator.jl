module FranklinLangs

include("css-flags.jl")
using .cssFlags: lang_to_country

using Gumbo
using Memoization
using Translator
using AbstractTrees: PreOrderDFS
using Franklin; const fr = Franklin
using LDJ.LDJFranklin: ldj_trans
using FranklinContent: canonical_url, post_link
using FranklinContent.Franklin: globvar, locvar, pagevar, path
using Translator: SLang
using URIs: URI
using Gumbo: HTMLElement, hasattr, setattr!, getattr

export hfun_langs_list, hfun_lang_links_html, get_languages, translate_website, sitemap_add_translations

@doc "Return the list of translated languages and the source language code."
@memoize function get_languages()
    (sort(globvar(:languages)), globvar(:lang_code))
end

@memoize ltc(code) = lang_to_country(code)

@doc "Generates an html dropdown language list (no css)."
function hfun_langs_list(usesvg=false)
    c = IOBuffer()
    write(c, "<ul class=\"lang-list\">")
    css_classes = usesvg ? "flag-icon flag-icon-" : "flag flag-"
    (tlangs, slang_code) = get_languages()
    for (lang, code) in tlangs
        # redirect source lang to default
        write(c, "<a class=\"lang-link lang-", code, "\" href=\"",
              post_link(locvar(:fd_rpath; default=""),
                        code === slang_code ? "" : code), "\">",
              "<span class=\"", css_classes, ltc(code), "\"></span>",
              lang, "</a>")
    end
    write(c, "</ul>")
    str = String(take!(c))
    close(c)
    str
end

@doc "Example callback for the translator to perform additional modifications
to the html file being processed."
function add_ld_data(el, file_path, url_path, pair)
    rpath = fr.get_rpath(joinpath(file_path, url_path))
    rpath = replace(rpath, r"__site/" => "")
    src_url = canonical_url(rpath)
    trg_url = post_link(url_path, pair.trg)

    # generates an ldj WebPage entity mentioning that the page
    # is a TranslationOfWork ...
    ldj_trans(file_path, src_url, trg_url, pair.trg) |>
        x -> convert(HTMLElement{:script}, x) |>
        x -> push!(el, x)

    # find canonical link and apply translation
    canonical = false
    amphtml = false
    for e in el.children
        if e isa HTMLElement{:link} &&
            hasattr(e, "rel")
            let rel = getattr(e, "rel")
                if rel === "canonical"
                    setattr!(e, "href", canonical_url(rpath;code=pair.trg))
                    canonical = true
                elseif rel === "amphtml"
                    setattr!(e, "href", canonical_url(rpath;code=pair.trg, amp=true))
                    amphtml = true
                end
                canonical && amphtml && break
            end
        end
    end
    src_url, trg_url
end

function hfun_lang_links_html()
    src_url = replace(locvar(:fd_rpath), r"__site/" => "") |> canonical_url
    set_lang_links!(src_url)
    join(string.(lang_links))
end

function set_transforms()
    let tf = Translator.tforms
        empty!(tf)
        tf[HTMLElement{:head}] = add_ld_data
    end
end

@doc "Example configuration function to define the translator lang and callbacks."
function config_translator(blog_dirs)
    # process franklin config; see `serve` function
    prepath = get(fr.GLOBAL_VARS, "prepath", nothing)
    fr.def_GLOBAL_VARS!()
    isnothing(prepath) || fr.set_var!(fr.GLOBAL_VARS, "prepath", prepath.first)
    fr.process_config()
    @assert !isnothing(fr.globvar(:website_url))

    # languages
    setlangs!((fr.globvar(:lang), fr.globvar(:lang_code)),
              fr.globvar(:languages))
    # html config
    sethostname!(fr.globvar(:website_url))
    push!(Translator.skip_class, "menu-lang-btn")
    set_transforms()
    # files
    push!(Translator.excluded_translate_dirs, :langs)
    if length(blog_dirs) > 0
        push!(Translator.included_translate_dirs, blog_dirs...)
    end
    Translator.load_db()
end

@doc "Recurses over a franklin processed site directory generating translated subdirectories."
function translate_website(;dir=nothing, method=trav_langs, blog_dirs=Set())
    isnothing(dir) && (dir = fr.path(:site))
    @assert !isnothing(dir)
    if isnothing(Translator.db.db)
        config_translator(blog_dirs)
    end
    try
        translate_dir(dir;method)
    catch e
        if e isa InterruptException
            display("Interrupted")
        else
            rethrow(e)
        end
    end
end

@inline function lang_url(code, url::URI; prefix="/")
    string(URI(url; path=(prefix * code * url.path)))
end

x_link_tag = Symbol(:(xhtml:link))
function make_lang_link(code, url; tag=x_link_tag)
    href = lang_url(code, url)
    el = HTMLElement(tag)
    setattr!(el, "rel", "alternate")
    setattr!(el, "hreflang", code)
    setattr!(el, "href", href)
    el
end

function make_amp_link(code, url)
    href = lang_url(code, url; prefix="/amp/")
    el = HTMLElement(link_tag)
    setattr!(el, "rel", "amphtml")
    setattr!(el, "hreflang", code)
    setattr!(el, "href", href)
    el
end

@doc "Include translated links to the urls in the sitemap."
function sitemap_add_translations(;amp=false)
    sitemap_path = joinpath(fr.path(:site), "sitemap.xml")
    sitemap = begin
        sm = read(sitemap_path, String) |> parsehtml
        sm.root |> PreOrderDFS |> collect
    end
    urls = begin
        @assert sitemap[4] isa HTMLElement{:urlset}
        collect(e for e in sitemap[5:end] if e isa HTMLElement{:url})
    end
    for u in urls
        loc = u[1]
        @assert loc isa HTMLElement{:loc}
        url_el = loc[1]
        url = URI(url_el.text)
        # add all translated langs to the url list
        target_langs, source_lang_code = get_languages()
        for (_, code) in target_langs
            code === source_lang_code && continue
            el = make_lang_link(code, url)
            push!(u, el)
            el = make_amp_link(code, url)
            push!(u, el)
        end
    end
    urlset = sm.root[2][1]
    @assert urlset isa HTMLElement{:urlset}
    setattr!(urlset, "xmlns:xhtml", "http://www.w3.org/1999/xhtml")
    open(sitemap_path, "w") do sf
        write(sf, """
        <?xml version="1.0" encoding="utf-8" standalone="yes" ?>
        """)
        write(sf, string(urlset))
    end
end

const lang_links = Vector{typeof(HTMLElement(:link))}()

function init_lang_links!()
    global lang_links
    if isempty(Translator.TLangs)
        config_translator(Set())
    else
        empty!(lang_links)
    end
    for lang in Translator.TLangs
        push!(lang_links, make_lang_link(lang.code, URI("/"); tag=:link))
    end
end

function set_lang_links!(url)
    isempty(lang_links) && init_lang_links!()
    for link in lang_links
        code = getattr(link, "hreflang")
        setattr!(link, "href", lang_url(code, URI(url)))
    end
    lang_links
end

end
