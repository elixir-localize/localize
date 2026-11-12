## Module structure

Every value attribute goes in one block before the first function definition, after any `use`, `import`, `alias` or `require`. A value attribute is a constant the module defines and reads — `@default_timeout 5_000`, `@known_usages [...]`, `@pattern ~r/.../`. Never define one between functions, and keep the comment explaining it with it.

Elixir reads an attribute at the point of use, so a constant defined at line 500 does not exist for any function above it — the compiler rejects `@foo` used before `@foo` is set. A mid-file constant partitions the module invisibly, and moving a function upward later breaks the build with an `undefined module attribute` pointing nowhere near the edit.

Attributes that describe a single definition stay with it and are not covered: `@doc`, `@moduledoc`, `@typedoc`, `@spec`, `@impl`, `@deprecated`, `@dialyzer {:nowarn_function, f: 1}`, `@compile {:inline, f: 1}`. `@type`, `@typep`, `@opaque`, `@callback` and `@enforce_keys` are declarations; keep them near the top unless they read better beside related code.

## Error returns from public API functions

Our objective is to return error tuples that can be both machine readable and can also produce localized human-readable messages.

* The standard non-error return is {:ok, return_value}

* An error return is {:error, MyAppError.exception(bindings)}

* bindings is a keyword list representing the data that will be used to form the exception message

## `with` expressions have no `else` clause

Every function in a `with` pipeline returns `{:ok, value}` or `{:error, exception}` of its own, so an unmatched value falls out of the `with` as the caller's return. An `else` clause means something in the chain returns the wrong shape — a bare `false`, a `nil`, a `:miss`, or an error the caller has to re-tag. Fix the callee, not the call site.

An `else` is also a latent crash: any value no clause matches raises `WithClauseError`. `Localize.Message.format_to_safe_list/3` matched only `ParseError` in its `else` while `parse_and_validate/2` also returned a `FormatError` for a data-model violation, so a duplicate `.local` declaration raised out of a function whose `@spec` promises an error tuple.

The codebase carries none: all 241 pre-existing `else` clauses were removed on 2026-10-11, across `lib`, `data` and `test`. So any `else` is new, and adding one needs agreement for that specific site plus an inline comment giving the reason.

## Exceptions

* Exceptions are stored in the lib/localize/exception directoy

* One exception is defined in one file

### Exception definition

An exception is defined as follows

```elixir
defmodule MyAppError do
  defexception [binding names]

  @impl true
  def exception(bindings) do
    %MyAppError{bindings}
  end
  
  @impl true
  def message(exception struct) do
    Gettext.dpgettext(Localize.Gettext, domain, msgctxt, msgid, bindings)  
  end
end
````

In the example above:

* domain - is always "localize"
* msgctxt - is a string representing which module of Localize we are working on. The main modules are "language_tag", "locale", "number", "datetime", "currency", "unit"
* msgid is the message string in Unicode Message Format 2 format with interpolation of the struct bindings
* bindings - the bindings derived from the struct

### Gettext extraction

Exception modules use `Gettext.dpgettext/5` (the runtime function) because they compile before the Gettext backend is available. This runtime function is invisible to `mix gettext.extract`. To ensure all exception messages appear in `.pot` files for translation, every message string must also be declared in `lib/localize/gettext/messages.ex` using `Gettext.Macros.dpgettext_noop_with_backend/4`. When adding or editing an exception file, always update `messages.ex` to match.

## Data pipeline

When changing the locale data generation pipeline (normalizers in `data/normalize/`, `@required_modules` in `data/locale.ex`, or any transform in `Localize.Data.Locale`), regenerate all locale ETF files to keep them up-to-date:

```bash
mix localize.generate_locales
```

The `:en` and `:und` locale ETFs are the only locales committed to the repository. Other locales are generated on-the-fly in `:dev` and `:test` environments.

The complete CLDR update process — source refresh, generation, conformance review, verification gates, CDN upload, hash manifest, release ordering — is documented in `CLDR_UPDATE_INTEGRATION.md` (the CLDR Update Guide). Consult it before any CLDR-version or data-pipeline work.

## Locale identifiers are atoms, never strings

The canonical locale identifier is an atom: `:en`, `:"en-GB"`, `:und`, `:"zh-Hant"`. It is what `cldr_locale_id` holds, what `Localize.supported_locales/0` returns and what every locale argument and option takes. A string locale identifier is a defect wherever it appears.

* **Write atoms everywhere:** library code, tests, doctests, `@doc` and guide examples, configuration examples, scratch scripts, reproductions, issue replies and commit messages. `Localize.validate_locale(:en)`, `locale: :"en-GB"`, `Localize.put_supported_locales([:"en-GB", :fi])`; never `"en"`, `"en-GB"` or `["en-GB", "fi"]`.

* **Match and compare on the atom.** Code that tests for a locale tests the atom (`:und`, never `"und"`), and a list of locale identifiers is a list of atoms. A check written against the string silently misses the canonical form: `best_match/3` excluded only `"und"` from matching, so `:und` in the supported list was matched as `en-Latn-US` and `en` resolved to `:und` (#71).

* **A string is input, not an identifier.** Text from outside (an `Accept-Language` header, a URL segment, a form field, a file) is a string only until `Localize.validate_locale/1` has turned it into a `%Localize.LanguageTag{}`, at the boundary where it arrives. Nothing past that boundary carries or compares a string, and a string is never converted with `String.to_atom/1`.

* **The subtag fields of a `%Localize.LanguageTag{}` are not locale identifiers** (`language: :en`, `script: :Latn`, `territory: :GB`) and keep the types the struct defines. `canonical_locale_id` is the BCP 47 string form of the whole tag, for display and serialisation; it is not the identifier a locale is looked up or compared by.

## Locale parsing

* When we need to parse or resolve a locale identifier, prefer `Localize.validate_locale/1` over `Localize.LanguageTag.parse/1`. Validation canonicalizes the tag, populates the `LanguageTag.U` struct for `-u-` extensions, resolves likely subtags, and caches the result.

## MessageFormat 2 (MF2) specification

The authoritative, up-to-date MF2 specification for this project is the CLDR repository checkout at:

```
../../cldr/cldr_repo/docs/ldml/tr35-messageFormat.md
```

(Absolute path on Kip's workstation: `/Users/kip/Development/cldr/cldr_repo/docs/ldml/tr35-messageFormat.md`.)

Always consult that file when auditing or extending the MF2 parser, the tree-sitter grammar, or any MF2-related feature — not a web-fetched copy, which may be stale. The `## message.abnf` section (around line 1398) contains the complete formal grammar. The `## Formatting`, `## Errors`, and `## Default Functions` sections are the reference for runtime behaviour.


