module FranklinLangs

include("css-flags.jl")
using .cssFlags: lang_to_country

using Gumbo
using Memoization
using LDJ.LDJFranklin: ldj_trans
using FranklinContent: canonical_url, post_link
using Translator: convert

export hfun_langs_list, get_languages, translate_website

@doc "Return the list of translated languages and the source language code."
@memoize function get_languages()
    (sort(globvar(:languages)), globvar(:lang_code))
end

@memoize ltc(code) = lang_to_country(code)

@doc "Generates an html dropdown language list (no css)."
function hfun_langs_list(usesvg=false)
    c = IOBuffer()
    write(c, "<ul id=\"lang-list\">")
    css_classes = usesvg ? "flag-icon flag-icon-" : "flag flag-"
    (tlangs, slang_code) = get_languages()
    for (lang, code) in tlangs
        # redirect source lang to default
        write(c, "<a class=\"lang-link\" id=\"lang-", code, "\" href=\"",
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
    src_url = canonical_url()
    trg_url = post_link(url_path, pair.trg)

    # generates an ldj WebPage entity mentioning that the page
    # is a TranslationOfWork ...
    ldj_trans(file_path, src_url, trg_url, pair.trg) |>
        x -> convert(HTMLElement{:script}, x) |>
        x -> push!(el, x)

    # find canonical link and apply translation
    for el in el.children
        if el isa HTMLElement{:link} &&
            hasattr(el, "rel") &&
            getattr(el, "rel") === "canonical"
            setattr!(el, "href", canonical_url(;code=pair.trg))
            break
        end
    end
end

function set_transforms()
    let tf = Translator.tforms
        empty!(tf)
        tf[HTMLElement{:head}] = add_ld_data
    end
end

@doc "Example configuration function to define the translator lang and callbacks."
function config_translator()
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
    Translator.load_db()
end

@doc "Recurses over a franklin processed site directory generating translated subdirectories."
function translate_website(;dir=joinpath(@__DIR__, "__site/"), method=Translator.trav_langs)
    if isnothing(Translator.SLang.code)
        config_translator()
    end
    try
        Translator.translate_dir(dir;method)
    catch e
        if e isa InterruptException
            display("Interrupted")
        else
            rethrow(e)
        end
    end
end

end
