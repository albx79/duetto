(lang dune 3.23)

(using menhir 3.0)

(name duetto)

(generate_opam_files true)

(source
 (github albx79/duetto))

(authors "Albx <albx79>")

(maintainers "Albx <albx79>")

(license LICENSE)

(documentation https://url/to/documentation)

(package
 (name duetto)
 (synopsis "spec and production in two voices")
 (description "An experimental programming language where specs define interfaces and check their conformance.")
 (depends ocaml)
 (tags
  ("add topics" "to describe" your project)))

; See the complete stanza docs at https://dune.readthedocs.io/en/stable/reference/dune-project/index.html
