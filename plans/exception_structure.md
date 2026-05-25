# Plan — Make every Localize exception semantically structured

**Date:** 2026-05-12
**Trigger:** the error shape below, surfaced from `mix localize.download_locales`:

```elixir
{:error,
 %Localize.FormatError{
   value: nil,
   function: nil,
   reason: "The locale :en could not be downloaded from \"https://elixir-localize.com/locales/v48.2.1/en.etf\": downloaded ETF failed safe decode."
 }}
```

The exception is doing none of its job. Two of its three fields are `nil`. Its `reason` field is not a code or an atom — it is the entire user-facing sentence, pre-rendered, with another error's path information baked in. The `message/1` callback is now redundant: the prose is already in the struct. Programmatic callers cannot pattern-match. Translators cannot retarget the string. The wrong exception type was used for the underlying failure (a download failure surfaced as a *format* error). And the underlying `LocaleDownloadError` was discarded — only its rendered text survived.

## Principle

Every Localize exception must:

1. **Carry only structured fields.** Identifiers, atoms, paths, struct values, integers, version structs. No field whose value is a free-form user-facing sentence.
2. **Render the user-facing string only in `message/1`.** That callback is the single place a sentence is assembled, and it does so by interpolating the structured fields through gettext.
3. **Use a `:reason` field only for a finite, documented set of atoms.** When `:reason` exists, the module's `message/1` must pattern-match it; a `_ -> ...` catch-all is a smell.
4. **Never flatten a wrapped exception to a string.** When a higher layer needs to report a lower layer's failure, the lower exception is preserved in a `:cause` field of the outer exception. `message/1` may delegate via `Exception.message(cause)` for the trailing detail.
5. **Use the *correct* exception type for the *current* layer.** A locale-download failure inside a status-line formatter is a `LocaleDownloadError`, not a `FormatError`. Wrap, don't relabel.

Once the principle is enforced, the failing call site in the trigger example becomes:

```elixir
%Localize.LocaleDownloadError{
  locale_id: :en,
  url: "https://elixir-localize.com/locales/v48.2.1/en.etf",
  reason: :safe_decode_failed
}
```

— with the human-readable sentence emerging only when something calls `Exception.message/1`.

---

## Findings — survey result

39 exception modules were reviewed. Verdicts:

| Verdict | Count | Modules |
|---|---|---|
| GOOD — structured, atom `:reason`, message/1 renders | 32 | (listed in Appendix A) |
| PARTIAL — has structured fields *and* a free-form string `reason`/`message`/`path` | 5 | `FormatError`, `LocaleDownloadError`, `LocaleCacheWriteError`, `ParseError`, plus one prose-stuffed `path` in `cache.ex:130` |
| BAD — bare `:message` field, no structure | 1 | `Localize.LanguageTag.ParseError` |

In addition, **11 call sites** stuff a fully-formed prose sentence into what should be a structural field. These are listed in §3 below.

---

## 1. Refactor the PARTIAL and BAD exception modules

### 1.1 — `Localize.FormatError` (PARTIAL → GOOD)

**Today:** [lib/localize/exception/format_error.ex](lib/localize/exception/format_error.ex)

```elixir
defexception [:value, :function, :reason]

def message(%{value: v, function: f, reason: reason}) when not is_nil(reason) do
  Gettext.dpgettext(..., "Cannot format {$value} with function {$function}: {$reason}",
    value: inspect(v), function: inspect(f), reason: reason)
end
```

The `:reason` field is interpolated verbatim. The interpolation works for any string, so callers stuff sentences in. `:value` and `:function` are documented but routinely `nil` at the call sites (e.g. [message.ex:94](lib/localize/message/message.ex:94)).

**Target shape:**

```elixir
defexception [:value, :function, :reason, :cause]

@type reason ::
        :unbound_variables
        | :bad_argument_type
        | :unsupported_function
        | :nif_unavailable
        | :downstream_failure   # use :cause to carry the underlying %Localize.*Error{}

@type t :: %__MODULE__{
        value: term() | nil,
        function: atom() | nil,
        reason: reason() | nil,
        cause: Exception.t() | nil
      }

def message(%__MODULE__{reason: :downstream_failure, cause: cause}) do
  # Render the underlying exception. No prose stored on this struct.
  Exception.message(cause)
end

def message(%__MODULE__{reason: :unbound_variables, value: vars}) do
  Gettext.dpgettext(Localize.Gettext, "localize", "message",
    "Cannot format message: unbound variables {$vars}",
    vars: inspect(vars))
end

def message(%__MODULE__{reason: :bad_argument_type, value: v, function: f}) do
  Gettext.dpgettext(Localize.Gettext, "localize", "message",
    "Cannot format {$value} with function {$function}: argument has an incompatible type",
    value: inspect(v), function: inspect(f))
end

# … one clause per reason atom; no string-interpolation clause.
```

**Migration of call sites:**

* [lib/localize/message/message.ex:94](lib/localize/message/message.ex:94) — the `format_elixir/3` clause currently passes `reason: reason` where `reason` came out of `Interpreter.format_list/3`. Replace with a case on the interpreter's tagged-tuple return:

  ```elixir
  {:format_error, {:bad_argument_type, value, function}} ->
    {:error, FormatError.exception(reason: :bad_argument_type, value: value, function: function)}
  ```

  Update `Localize.Message.Interpreter` to return tagged tuples instead of strings.

* [lib/localize/message/message.ex:391](lib/localize/message/message.ex:391) — `Localize.FormatError.exception(value: message, function: :format, reason: reason)`. Same treatment.

* The trigger-case path inside `mix localize.download_locales`: the message formatter is currently catching a download error and surfacing it as a `FormatError`. Fix this at the call site — `Localize.Message.format/2` should propagate the inner exception:

  ```elixir
  case download_locale(locale_id) do
    {:ok, _} = ok -> ok
    {:error, %_{} = cause} ->
      {:error, FormatError.exception(reason: :downstream_failure, cause: cause)}
  end
  ```

  Better yet, **do not wrap** — return the `LocaleDownloadError` directly from `Localize.Message.format/2` when the failure cause is unrelated to message formatting. Wrapping is only appropriate when the caller would not recognise the inner type. In this case the inner type *is* the right diagnosis.

---

### 1.2 — `Localize.LocaleDownloadError` (PARTIAL → GOOD)

**Today:** [lib/localize/exception/locale_download_error.ex](lib/localize/exception/locale_download_error.ex)

```elixir
defexception [:locale_id, :url, :reason]

def message(%{locale_id: id, url: url, reason: reason}) do
  Gettext.dpgettext(..., "The locale {$locale_id} could not be downloaded from {$url}: {$reason}.",
    locale_id: inspect(id), url: inspect(url), reason: to_string(reason))
end
```

`:reason` is fed `inspect(reason)` from `Localize.Utils.Http.get/1` at [lib/localize/locale/provider.ex:497](lib/localize/locale/provider.ex:497) and the literal string `"not modified"` at line 489. Both are prose; one is a stringified Erlang term.

**Target shape:**

```elixir
defexception [:locale_id, :url, :reason, :http_status, :cause]

@type reason ::
        :not_modified
        | :http_error            # use :http_status and :cause
        | :network_error         # :cause holds the inet error term
        | :safe_decode_failed    # cache loader rejected the body
        | :stale_version         # downloaded body did not match expected version

@type t :: %__MODULE__{
        locale_id: atom(),
        url: String.t(),
        reason: reason(),
        http_status: 100..599 | nil,
        cause: term() | nil
      }

def message(%__MODULE__{reason: :not_modified, locale_id: id, url: url}) do
  Gettext.dpgettext(Localize.Gettext, "localize", "locale",
    "The locale {$locale_id} at {$url} is unchanged since the last download.",
    locale_id: inspect(id), url: url)
end

def message(%__MODULE__{reason: :http_error, locale_id: id, url: url, http_status: status}) do
  Gettext.dpgettext(Localize.Gettext, "localize", "locale",
    "The locale {$locale_id} could not be downloaded from {$url}: HTTP {$status}.",
    locale_id: inspect(id), url: url, status: status)
end

# … one clause per reason atom.
```

`Localize.Utils.Http.get/1` should be updated to return one of `{:ok, body}`, `{:not_modified, headers}`, `{:error, {:http, status}}`, `{:error, {:transport, posix_error}}` so the provider can map cleanly into the new reason atoms.

---

### 1.3 — `Localize.LocaleCacheWriteError` (PARTIAL → GOOD)

**Today:** [lib/localize/exception/locale_cache_write_error.ex](lib/localize/exception/locale_cache_write_error.ex)

`:reason` receives `inspect(file_error)` from `File.mkdir_p/1` or `File.write/2`. The `:path` field is sometimes prose-stuffed at [lib/localize/locale/provider/cache.ex:130](lib/localize/locale/provider/cache.ex:130):

```elixir
path: "#{file_path} (#{inspect(reason)})"
```

— a *path* field containing a path **plus** a parenthetical Erlang reason. That is the pathological case: structural information from one field has been melted into another field's prose.

**Target shape:**

```elixir
defexception [:locale_id, :path, :reason, :posix_error]

@type reason ::
        :permission_denied
        | :no_such_directory
        | :disk_full
        | :read_only_filesystem
        | :other_io_error  # :posix_error carries the raw atom from :file

@type t :: %__MODULE__{
        locale_id: atom(),
        path: Path.t(),
        reason: reason(),
        posix_error: :file.posix() | nil
      }

def message(%__MODULE__{reason: :permission_denied, path: path, locale_id: id}) do
  Gettext.dpgettext(Localize.Gettext, "localize", "locale",
    "Cannot write locale {$locale_id} to {$path}: permission denied.",
    locale_id: inspect(id), path: path)
end

# … one clause per reason atom.
```

Map known POSIX errors (`:eacces`, `:enoent`, `:enospc`, `:erofs`) to reason atoms in `exception/1`; everything else falls through to `:other_io_error` with the raw atom preserved in `:posix_error`.

Update [cache.ex:101-132](lib/localize/locale/provider/cache.ex:101) so the `:path` field always holds a raw `Path.t()` — never a path-plus-parens. The Erlang reason goes into `:posix_error`.

---

### 1.4 — `Localize.ParseError` (PARTIAL → GOOD)

**Today:** [lib/localize/exception/parse_error.ex](lib/localize/exception/parse_error.ex)

`:input`, `:offset`, `:line`, `:column`, `:rest` are structural — good. `:reason` is a free-form string in every call site:

* [lib/localize/message/parser/parser.ex:40](lib/localize/message/parser/parser.ex:40) — `"unexpected trailing input #{inspect(rest)}"`.
* [lib/localize/unit/parser.ex:47](lib/localize/unit/parser.ex:47) — `"Could not parse the remaining #{inspect(rest)} starting at position #{offset + 1}"`.
* [lib/localize/unit/parser.ex:55](lib/localize/unit/parser.ex:55) — `"#{reason}. Could not parse the remaining #{inspect(rest)} at position #{offset + 1}"`.

Both already pass `:input`, `:rest`, `:offset` as structural fields — they then *also* repeat the same information in prose form in `:reason`. The `reason` field can go.

**Target shape:**

```elixir
defexception [:input, :reason, :offset, :line, :column, :rest, :expected]

@type reason ::
        :unexpected_trailing_input  # :rest carries the unconsumed bytes
        | :unexpected_token         # :rest carries the unconsumed bytes
        | :incomplete_input         # parser hit end-of-input mid-rule
        | :nimble_parsec_error      # :expected carries the parser's expectation

@type t :: %__MODULE__{
        input: String.t(),
        reason: reason(),
        offset: non_neg_integer() | nil,
        line: pos_integer() | nil,
        column: pos_integer() | nil,
        rest: String.t() | nil,
        expected: String.t() | nil
      }

def message(%__MODULE__{reason: :unexpected_trailing_input, input: input,
                         rest: rest, line: l, column: c}) when is_integer(l) do
  Gettext.dpgettext(Localize.Gettext, "localize", "message",
    "Could not parse {$input}: unexpected trailing input {$rest} at line {$line} column {$column}",
    input: inspect(input), rest: inspect(rest), line: l, column: c)
end

# … one clause per (reason, location-shape) pair.
```

NimbleParsec's own error string can populate `:expected` rather than `:reason`. Translators get to retarget each reason independently.

---

### 1.5 — `Localize.LanguageTag.ParseError` (BAD → GOOD)

**Today:** [lib/localize/language_tag/parse_error.ex](lib/localize/language_tag/parse_error.ex)

```elixir
defmodule Localize.LanguageTag.ParseError do
  @moduledoc false
  defexception [:message]

  def exception(message) do
    %__MODULE__{message: message}
  end
end
```

A bare `:message` field accepting a pre-rendered string. No structure at all. Worse, it's `@moduledoc false`, so its existence is half-hidden.

**Recommendation:** delete this module entirely. Every site that raises it should raise `Localize.ParseError` instead (which is the public-API exception for parse failures of language tags, MF2 messages, and unit identifiers, per its own moduledoc). `git grep` for `Localize.LanguageTag.ParseError` to find call sites and migrate each to `Localize.ParseError.exception/1` with structured fields.

---

## 2. Fix the prose-stuffed structural fields in GOOD modules

These modules have the right *shape* but at least one call site abuses a structural field with prose. The fix is to add a new structural field (typically an atom plus the values it interpolates) and let the existing `message/1` clause assemble the sentence.

### 2.1 — `Localize.InvalidValueError.expected` (multiple sites)

**Today** the `:expected` field is documented as a description of the valid range, but several call sites pass a complete sentence with an embedded list of valid values:

* [lib/localize/unit.ex:693](lib/localize/unit.ex:693) — `expected: "a valid usage (one of: #{Enum.join(valid, ", ")})"`
* [lib/localize/datetime/relative.ex:259](lib/localize/datetime/relative.ex:259) — `expected: "a valid time unit: #{inspect(@unit_keys)}"`
* [lib/localize/datetime/relative.ex:270](lib/localize/datetime/relative.ex:270) — `expected: "one of #{inspect(@known_formats)}"`
* [lib/localize/number/symbol.ex:105](lib/localize/number/symbol.ex:105) — `expected: "a valid number system for locale #{inspect(locale_id)}"`
* [lib/localize/number/format/options.ex:267](lib/localize/number/format/options.ex:267) — `expected: "a valid rounding mode (#{inspect(@rounding_modes)})"`

**Fix:** widen the struct so `:expected` is a structural value, then move the sentence into `message/1`.

```elixir
defexception [:value, :expected, :allowed_values, :context]

@type t :: %__MODULE__{
        value: term(),
        expected: atom() | nil,        # e.g. :usage, :time_unit, :rounding_mode
        allowed_values: [term()] | nil,
        context: term() | nil
      }

def message(%__MODULE__{value: v, expected: :usage, allowed_values: allowed, context: ctx}) do
  Gettext.dpgettext(Localize.Gettext, "localize", "unit",
    "Invalid usage {$value} for category {$category}: expected one of {$allowed}",
    value: inspect(v), category: inspect(ctx), allowed: inspect(allowed))
end

# … one clause per :expected atom.
```

Each call site becomes structural, e.g. at `lib/localize/unit.ex:693`:

```elixir
InvalidValueError.exception(
  value: usage,
  expected: :usage,
  allowed_values: valid,
  context: category
)
```

### 2.2 — `Localize.UnknownCurrencyError.currency` is sometimes a sentence

* [lib/localize/number/parser.ex:201](lib/localize/number/parser.ex:201) — `currency: "#{string} is unknown or not supported"`
* [lib/localize/currency.ex:218](lib/localize/currency.ex:218) — `currency: "No currencies for #{inspect(territory)} were found"`

The first is a true unknown-currency case and should pass `currency: string`.

The second is **not** an unknown-currency at all — it's "no currencies for this territory". Wrong exception type. Introduce `Localize.NoCurrenciesForTerritoryError` with `[:territory]`, or reuse `Localize.ItemNotFoundError` with `keys: [:currencies, territory]`.

### 2.3 — `Localize.ParseError.reason` prose in three parsers

Already covered in §1.4. Listed here for cross-reference:

* `lib/localize/message/parser/parser.ex:40`
* `lib/localize/unit/parser.ex:47`
* `lib/localize/unit/parser.ex:55`

### 2.4 — `Localize.LocaleCacheWriteError.path` prose in `cache.ex:130`

Already covered in §1.3.

---

## 3. Replace `raise ArgumentError`/`RuntimeError` with structured exceptions

Eight sites in `lib/` raise built-in Elixir exceptions with interpolated messages. These should each become a Localize exception with structural fields. They are the same pattern as the call sites in §2 but with a wider blast radius — built-in exceptions cannot be pattern-matched on type by callers who want to handle Localize-specific failures.

| Call site | Replace with |
|---|---|
| [lib/localize/language.ex:262](lib/localize/language.ex:262) — invalid `:style` | `Localize.InvalidValueError{value: style, expected: :style, allowed_values: @styles}` |
| [lib/localize/language.ex:270](lib/localize/language.ex:270) — invalid `:fallback` | `Localize.InvalidValueError{value: fallback, expected: :fallback, allowed_values: [true, false]}` |
| [lib/localize/script.ex:245](lib/localize/script.ex:245) — invalid `:style` | as above |
| [lib/localize/script.ex:253](lib/localize/script.ex:253) — invalid `:fallback` | as above |
| [lib/localize/collation/options.ex:173](lib/localize/collation/options.ex:173) — invalid `:casing` | `Localize.InvalidValueError{value: other, expected: :casing, allowed_values: [:sensitive, :insensitive]}` |
| [lib/localize/utils/http.ex:356](lib/localize/utils/http.ex:356) — no CA trust store | new `Localize.NoCertificateStoreError{searched: [...]}` |
| [lib/localize/utils/map.ex:1083](lib/localize/utils/map.ex:1083) — bad function arg | `Localize.InvalidValueError{value: function, expected: :function_or_2_tuple}` |
| [lib/localize/utils/map.ex:1100](lib/localize/utils/map.ex:1100) — bad `:level` arg | `Localize.InvalidValueError{value: other, expected: :level_integer_or_range}` |
| [lib/localize/utils/math.ex:1034](lib/localize/utils/math.ex:1034) — bad arith | leave as `ArithmeticError`; this is the Elixir-standard exception for this case |

For each, update the surrounding spec and let the upstream caller branch on the structured `:expected` atom.

---

## 4. Cross-cutting work

### 4.1 — Add a `:cause` field convention

When a higher layer must wrap a lower exception (rather than propagating it unchanged), the outer struct gets a `:cause` field of type `Exception.t() | nil`. The convention:

* `:cause` is set when, and only when, the outer exception is a wrapper. A direct error sets `:cause` to `nil`.
* The outer `message/1` may delegate to the inner via `Exception.message(cause)`, possibly with a leading context phrase.
* Programmatic callers can pattern-match on the outer type for the operation context, and `Exception.message/1` on `:cause` for the original detail.

Apply this in `FormatError`, `LocaleCacheWriteError`, and `LocaleDownloadError`. Document the convention in `Localize` exceptions' grouping doc.

### 4.2 — Add `Localize.Exception` behaviour (optional, low priority)

A behaviour that declares `@callback message/1` is redundant — `Exception` already does that. But a behaviour declaring `@callback reason_atoms/0 :: [atom()]` would force every module to list its valid `:reason` values, enabling a compile-time test that `message/1` has a clause for each. Worth considering if the `:reason` set grows much further.

### 4.3 — Tests

Add a property-style test per refactored module: for each documented `:reason` atom, build the exception with realistic field values, call `Exception.message/1`, and assert the result is a non-empty binary not containing `inspect/1` artefacts of the struct itself (no `"%Localize."`). This catches the failure mode where a new reason atom is added to `defexception` but the `message/1` clause is forgotten — `Gettext.dpgettext` would fall through to a default that exposes the struct's inspect form.

### 4.4 — Gettext POT regeneration

After the refactor, every `message/1` clause is its own gettext template. Regenerate the POT and have translators retarget. Old keys for the deleted prose templates can be removed.

---

## 5. Migration order

1. **Add the new exception fields without removing the old.** `FormatError` gets `:cause`; `LocaleDownloadError` gets `:http_status` and `:cause`; `LocaleCacheWriteError` gets `:posix_error`; `ParseError` gets `:expected`. Module behaviour is unchanged at this point.
2. **Update `message/1` to dispatch on `:reason` atoms first, falling through to the existing prose-rendering clause** for unmigrated call sites. This lets the test suite stay green between steps.
3. **Migrate call sites one by one**, replacing prose `:reason` strings with reason atoms and populating the new structural fields.
4. **Delete the fallback prose clause from `message/1`** once `git grep` shows no callers using the old shape.
5. **Delete `Localize.LanguageTag.ParseError`** after migrating its raisers to `Localize.ParseError`.
6. **Replace `raise ArgumentError`/`RuntimeError` sites** (§3). These can be done in parallel with §1.
7. **Regenerate POT** and update tests.

Each step is independently shippable; the suite stays green between them. The whole effort is mechanical once §1 is in.

---

## Appendix A — GOOD modules (no work needed)

`BindError`, `CurrencyNoDisplayNameError`, `DateTimeFormatError`, `DateTimeIntervalFormatError`, `DateTimeInvalidInputError`, `DateTimeUnresolvedFormatError`, `InvalidLocaleError`, `InvalidSubtagError`, `InvalidValueError` (modulo §2.1), `ItemNotFoundError`, `LikelySubtagsError`, `LocaleDisplayError`, `LocaleIsStaleError`, `LocaleMatchError`, `LocaleNotFoundInCacheError`, `NoParentError`, `NoParentTerritoryError`, `UnitConversionError`, `UnitNoValueError`, `UnitPreferenceError`, `UnknownCalendarError`, `UnknownCurrencyError` (modulo §2.2), `UnknownLanguageError`, `UnknownLocaleError`, `UnknownMeasurementSystemError`, `UnknownNumberSystemError`, `UnknownPluralRulesError`, `UnknownRbnfRuleError`, `UnknownScriptError`, `UnknownStyleError`, `UnknownSubdivisionError`, `UnknownTerritoryError`, `UnknownTimezoneError`, `UnknownUnitError`.

These use a consistent pattern: structured fields only, and `message/1` either renders them directly or dispatches on an atom-valued `:reason`. They are the template to copy.

---

## Plan complete.

