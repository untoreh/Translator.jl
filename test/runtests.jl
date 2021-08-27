using Translator
using Aqua

Aqua.test_ambiguities(Translator)
Aqua.test_stale_deps(Translator; ignore=[:Aqua])
Aqua.test_unbound_args(Translator)
Aqua.test_project_toml_formatting(Translator)
Aqua.test_undefined_exports(Translator)
# Aqua.test_deps_compat(Translator)
Aqua.test_project_extras(Translator)
