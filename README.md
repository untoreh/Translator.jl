# Translator.jl

Translates html using other translator services.

# Configuration

``` julia
using Translator

# Set the source language (Tuple{Str, Str}) and the target languages (Vector{Tuple})
setlangs!((fr.globvar(:lang), fr.globvar(:lang_code)),
            fr.globvar(:languages))
            
# Urls matching this host will be rewritten
sethostname!(fr.globvar(:website_url))

# Ignore some elements
push!(Translator.skip_class, "menu-lang-btn")

# Don't translate files in these directories
push!(Translator.excluded_translate_dirs, :langs)

# Map a function to perform custom transformations to specific html tags
# (it is applied to all elements matching the type, which is a Gumbo.jl type)
# my_func arguments are (html_element, base_file_path, url_relative_path, language_pair)
Translator.transforms[HTMLElement{:head}] = my_func

# Use a KV store for caching translations
Translator.load_db()
```

# Usage
Translating over a directory can be done by files or by langs. 
- By files: on every file translation is applied for every language. It iterates only once over the directory tree.

- By lang: on every target lang translation is applied for every file. Iterates over the directory tree as many as there are target languages, handles batched translations better. It is more useful when there is already a large cache of translations and files only require minimal updates.

``` julia
method = Translator.trav_files
dir = "my/directory/path"

Translator.translate_dir(dir;method)
```

## Translation services
Services are implemented with `PyCall`... wrapping other python wrappers.
There is also support for offline translation through [argos translate](https://github.com/argosopentech/argos-translate), although it is quite slow for html.

## Translate a Franklin website
In your utils file add this line.

``` julia
using Translator: franklinlangs; franklinlangs(); using Translator.FranklinLangs
```

Then call the translation. For other customizations see how [it is implemented](/src/misc/franklin.jl)

``` julia
translate_website()
```
