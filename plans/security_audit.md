# Localize — Security & Denial-of-Service Audit

**Audit date:** 2026-05-10
**Audit target:** `localize` v0.28.0 (branch `claude/goofy-mccarthy-592149`)
**Scope:** Static review of public API surface for security-relevant defects. Focus areas: input handling on data crossing trust boundaries (user-supplied locale strings, format strings, message strings), unbounded-resource conditions, atom exhaustion, NIF safety, file/path handling, regex usage, ETS / caching behaviour.

This audit deliberately treats `localize` as a *library that may be called with attacker-controlled input* — for example a web service that accepts an `Accept-Language` header, a locale identifier from a query string, a message template loaded from user-uploaded content, a number to be parsed, or a unit string from a third-party API. Findings are categorised by severity and include concrete reproduction notes where applicable.

> **Status:** in progress. This document is being written incrementally and should be considered a working draft until the "Audit complete" marker appears at the end.

---

## Threat model

Two deployment shapes are considered:

1. **Server / API**. The library is called from a web service that processes untrusted input. Locale strings, language tags, message templates, number/unit strings, and format strings may all originate from a remote attacker. The blast radius of a defect here includes: process crash, unbounded memory growth, atom-table exhaustion (which downs the BEAM globally), CPU exhaustion that locks a request scheduler, ETS/cache poisoning that affects other tenants, and information disclosure (filesystem paths, internal state).

2. **Local tooling / CLI**. The library is called with input the operator controls. The realistic threats here are operator-mistake-shaped — a malformed CLDR data file, a corrupted locale ETF, a user-supplied template that should fail loudly rather than silently produce wrong output. Most server-side findings still apply, but with lower urgency.

The library is not a sandbox. It does not promise to safely process malicious CLDR data, malicious ETF, or malicious compiled `.beam` files. The audit therefore focuses on the **runtime API surface** (the functions a typical caller invokes), not on the data-loader / build-time path that ingests CLDR XML.

---

## Findings index

Severity scale:

* **High** — exploitable from the public API with caller-shaped input; can crash the BEAM, exhaust the global atom table, lock a scheduler, or execute arbitrary code.
* **Medium** — exploitable but with caveats (large input, niche surface, indirect reach), or causes per-process resource exhaustion rather than node-wide damage.
* **Low** — limited blast radius, requires unrealistic preconditions, or already documented as caller-beware.
* **Info** — not a bug; recorded so a later auditor knows the spot has already been considered.

| # | Finding | Severity | File:line |
|---|---|---|---|
| 1 | Language tag parser creates unbounded atoms from caller subtags | High | [lib/localize/language_tag/parser.ex:76](lib/localize/language_tag/parser.ex:76) |
| 2 | `Localize.Locale.to_locale_id/1` calls `String.to_atom/1` on caller binary | High | [lib/localize/locale.ex:644](lib/localize/locale.ex:644) |
| 3 | Currency-filter accepts binary code and atomises it | High | [lib/localize/currency.ex:1008](lib/localize/currency.ex:1008) |
| 4 | Locale-display IANA zone splitter atomises caller substrings | High | [lib/localize/locale/locale_display/u.ex:355](lib/localize/locale/locale_display/u.ex:355) |
| 5 | NIF: no functions tagged `ERL_NIF_DIRTY_JOB_CPU_BOUND` — caller-bound work runs on a normal scheduler | High | [c_src/localize_nif.cpp:908](c_src/localize_nif.cpp:908) |
| 6 | NIF: reorder-codes binary length cast `size_t → int32_t` then drives `enif_alloc` | High | [c_src/localize_nif.cpp:527](c_src/localize_nif.cpp:527) |
| 7 | Locale-cache `binary_to_term/1` without `[:safe]` on filesystem-supplied bytes | High | [lib/localize/locale/provider/cache.ex:104](lib/localize/locale/provider/cache.ex:104) |
| 8 | MessageFormat / unit parsers use unbounded `repeat()` and recursive structure | Medium | [lib/localize/message/parser/parser.ex:31](lib/localize/message/parser/parser.ex:31) |
| 9 | `Localize.Number.parse/2` accepts unbounded length and unbounded Decimal exponent | Medium | [lib/localize/number/parser.ex:100](lib/localize/number/parser.ex:100) |
| 10 | NIF: `std::stoll` / `std::stod` without try/catch can throw and unwind into BEAM | Medium | [c_src/localize_nif.cpp:641](c_src/localize_nif.cpp:641) |
| 11 | NIF: locale / pattern strings forwarded to ICU with no length cap | Medium | [c_src/localize_nif.cpp:345](c_src/localize_nif.cpp:345) |
| 12 | Format cache is `:public` ETS, bounded only by a 10-second sweeper | Medium | [lib/localize/format_cache.ex:98](lib/localize/format_cache.ex:98) |
| 13 | `Localize.Unit.CustomRegistry.load_file/1` evaluates arbitrary Elixir | Low (by design) | [lib/localize/unit/custom_registry.ex:158](lib/localize/unit/custom_registry.ex:158) |
| 14 | `binary_to_term/1` on bundled `priv/*.etf` without `[:safe]` | Low | [lib/localize/supplemental_data.ex:17](lib/localize/supplemental_data.ex:17) |
| 15 | `Localize.LanguageTag.parse/1` accepts unbounded input length | Medium | [lib/localize/language_tag.ex:204](lib/localize/language_tag.ex:204) |

The remainder of this document expands each finding, gives a reproduction sketch, and proposes a remediation. Findings are grouped by class.

---

## 1. Atom-table exhaustion

The BEAM atom table is a global, mostly-finite resource. The default cap is 1,048,576 entries. Once it fills, the VM aborts with `system_limit` and the entire node dies — every other process, every other tenant, every supervisor goes with it. There is no way to garbage-collect atoms (except for special "garbage-collected literals" which do not apply here). Any code path that turns caller input into an atom via `String.to_atom/1`, `:erlang.binary_to_atom/2` (without `:safe`), `List.to_atom/1`, or `Module.concat/{1,2}` is a node-wide DOS vector if the input space is large enough that an attacker can make the path produce many distinct atoms.

`String.to_existing_atom/1` is **not** a vulnerability — it raises if the atom is unknown. `:erlang.binary_to_atom(b, :latin1)` and `:erlang.binary_to_atom(b, :utf8)` **are** vulnerabilities. The audit found four runtime, attacker-influenceable atom-creation sites in the public API.

### 1.1 — Language tag parser atomises every subtag (High)

**Location:** [lib/localize/language_tag/parser.ex:75-85](lib/localize/language_tag/parser.ex:75)

```elixir
def normalize_field({:language = field, language}) do
  {field, language |> Localize.Validity.Language.normalize() |> String.to_atom()}
end

def normalize_field({:script = field, script}) do
  {field, script |> Localize.Validity.Script.normalize() |> String.to_atom()}
end

def normalize_field({:territory = field, territory}) do
  {field, territory |> Localize.Validity.Territory.normalize() |> String.to_atom()}
end
```

The implicit assumption is that `Localize.Validity.Language.normalize/1` returns only canonical, validated codes. It does not — see [lib/localize/validity/language.ex:26-28](lib/localize/validity/language.ex:26):

```elixir
def normalize(code) when is_binary(code) do
  String.downcase(code)
end
```

`normalize/1` lowercases. It does not check the input against the validity set. The same is true for `Validity.Script.normalize/1` and `Validity.Territory.normalize/1`. The grammar that produces the input to these calls (`lib/localize/language_tag/rfc5646/`) restricts language subtags to `2*3ALPHA / 4ALPHA / 5*8ALPHA` and script subtags to exactly `4ALPHA`. ASCII alpha is a 26-character alphabet, but:

* Language subtag (5–8 chars after the BCP-47 alternation): 26⁵ + 26⁶ + 26⁷ + 26⁸ ≈ 2.1 × 10¹¹ unique strings.
* Script subtag (4 chars): 26⁴ = 456 976 unique strings.

The atom table caps at ~1M atoms by default. **Either subspace alone is large enough to fill the table, and an attacker can drive either by feeding `Localize.LanguageTag.parse/1` (or any function that funnels into it — e.g. `Localize.validate_locale/1`, `Localize.Locale.new/1`) a stream of distinct random subtags.**

**Reproduction (sketch):**

```elixir
# Crash a node in O(seconds) on default settings.
for _ <- 1..2_000_000 do
  tag = for _ <- 1..6, into: <<>>, do: <<Enum.random(?a..?z)>>
  Localize.LanguageTag.parse(tag)
end
```

**Severity:** **High**. Reachable from any function that accepts a locale string from caller input. Includes the natural shape of an `Accept-Language` header parser that ends up calling `LanguageTag.parse/1` per element.

**Remediation:** in `normalize_field`, only emit an atom if the normalised code is in the validity set. Otherwise fall back to either keeping the binary in the field (changing the struct contract — explicitly fail) or returning `{:error, _}` and letting `validate/1` reject it. Calling `String.to_existing_atom/1` is not enough on its own because the validity set is small enough that an attacker could still iterate through it; the actual fix is to **fail the parse** when a subtag is not a known code and never atomise unknown input.

### 1.2 — `Localize.Locale.to_locale_id/1` directly atomises a binary (High)

**Location:** [lib/localize/locale.ex:639, 644-645](lib/localize/locale.ex:644)

```elixir
def to_locale_id(%LanguageTag{} = tag) do
  case Localize.validate_locale(tag) do
    {:ok, %{cldr_locale_id: resolved}} when not is_nil(resolved) -> resolved
    _ -> tag |> LanguageTag.to_string() |> String.to_atom()
  end
end

def to_locale_id(locale_id) when is_atom(locale_id), do: locale_id
def to_locale_id(locale_id) when is_binary(locale_id), do: String.to_atom(locale_id)
def to_locale_id(locale_id), do: String.to_atom(inspect(locale_id))
```

Three separate atom-creation sites:

1. Line 639 — fallback for an unvalidatable language tag falls back to atomising the rendered string. Reachable when `validate_locale/1` returns `{:error, _}` for a parsed-but-unrecognised tag.
2. Line 644 — direct atomisation of a binary locale id.
3. Line 645 — `String.to_atom(inspect(locale_id))` will atomise the inspected form of literally anything, including a list, map, or PID. Inspect output is unbounded and includes structural detail.

**Severity:** **High**. The function is documented as canonicalising a locale id, so callers will pass user-supplied locale strings here and reasonably expect either a valid atom or an error.

**Remediation:** every branch should use `String.to_existing_atom/1` (and rescue `ArgumentError` to return an error or `nil`), or — better — call `Localize.validate_locale/1` and propagate `{:error, _}` rather than coerce to a fresh atom. The line-645 catch-all (`inspect(locale_id) |> String.to_atom()`) should be replaced with an explicit raise or `{:error, :invalid_locale}`, since the only way it triggers is on a totally malformed argument and silently atomising garbage hides the bug *and* fills the atom table.

### 1.3 — Currency filter atomises caller binary (High)

**Location:** [lib/localize/currency.ex:1004-1009](lib/localize/currency.ex:1007)

```elixir
code when is_atom(code) ->
  Enum.filter(currencies_list, fn {k, _} -> k == code end)

code when is_binary(code) ->
  atom_code = String.to_atom(code)
  Enum.filter(currencies_list, fn {k, _} -> k == atom_code end)
```

The atom is created **before** the filter check, so even codes that match nothing in `currencies_list` still produce a permanent atom. Reachable from `Localize.Currency.currencies_for/2` and friends when callers pass binary codes (entirely natural — currencies are typically supplied as `"USD"`, not `:USD`, especially when sourced from an external system).

**Severity:** **High**. The currency-code keyspace is small (~3 letters × 26 = 17 576 plus longer strings), but because the binary clause atomises **before** matching, an attacker can submit any binary at all — e.g. `"AAA1"`, `"AAA2"`, … — and each one produces an atom. The keyspace is unbounded.

**Remediation:** swap the order — use `Helpers.existing_atom/1` (already in the codebase, e.g. used by `lib/localize/locale/locale_display/u.ex:149`), or do the filter on string equality after `to_string/1` on each `k`, never atomising caller input.

```elixir
code when is_binary(code) ->
  case Localize.Utils.Helpers.existing_atom(code) do
    nil -> []
    atom_code -> Enum.filter(currencies_list, fn {k, _} -> k == atom_code end)
  end
```

### 1.4 — Locale-display zone splitter atomises IANA components (High)

**Location:** [lib/localize/locale/locale_display/u.ex:353-361](lib/localize/locale/locale_display/u.ex:355)

```elixir
case String.split(iana_id, "/", parts: 2) do
  [region, city] ->
    region_key = region |> String.downcase() |> String.to_atom()
    city_key = city |> String.downcase() |> String.replace(" ", "_") |> String.to_atom()

    case get_in(zone, [region_key, city_key]) do
      %{city: city_name} -> city_name
      _ -> nil
    end
```

`iana_id` originates from the `tz` parameter of a `u`-extension on a parsed BCP-47 tag. A caller can submit any tag of the form `"en-u-tz-attacker/payload"` and reach this code path. Each unique `region/city` pair produces two atoms.

**Severity:** **High**. The character class permitted by the `u`-extension grammar is broad (alphanumeric subtags up to 8 characters), and `String.replace(" ", "_")` shows the function is prepared to handle non-canonical input. There is no whitelist gate before the atom call.

**Remediation:** use the `safe_to_atom` helper already defined in the same module (`lib/localize/locale/locale_display/u.ex:148`), which falls back to `nil`/string when no atom exists. Then short-circuit the lookup if either key is missing.

### 1.5 — Other atomisation sites (Low — noting for completeness)

* [lib/localize/locale/locale_display/u.ex:142](lib/localize/locale/locale_display/u.ex:142) routes through `safe_to_atom/1` (returns the original string when no atom exists) — safe.
* [lib/localize/locale/locale_display/t.ex:343](lib/localize/locale/locale_display/t.ex:343) likewise routes through `to_atom_safe/1` which uses `Helpers.existing_atom(value) || String.to_atom(value)`. **Wait — that fallback to `String.to_atom/1` is unsafe.** Re-examined below.
* [lib/localize/gettext/interpolation.ex:132](lib/localize/gettext/interpolation.ex:132) also uses `existing_atom(name) || String.to_atom(name)`.

**Update — locale_display/t.ex:342-343 is also a vector (High).** The naming suggests safety, but the implementation is:

```elixir
defp to_atom_safe(value) when is_binary(value),
  do: Helpers.existing_atom(value) || String.to_atom(value)
```

Falling through to `String.to_atom/1` defeats the purpose of the helper. Same issue at `gettext/interpolation.ex:132`. Both should return `nil` or the raw string and let the caller decide, never atomise on miss.

Compile-time atom creation in `data/` (CLDR data normalisation) and in macro-expanded code is not a concern — those atoms are interned once at compile time and bounded by the CLDR dataset.

---

## 2. NIF: ICU bindings (`c_src/localize_nif.cpp`)

The NIF wraps ICU and exposes six functions: `nif_mf2_validate/1`, `nif_mf2_format/3`, `nif_collation_cmp/10`, `nif_plural_rule/4`, `nif_number_format/4`, `nif_unit_format/4`. The NIF is opt-in (`LOCALIZE_NIF=true` or `config :localize, :nif, true`); when disabled the library uses pure-Elixir paths. When enabled, the NIF runs in the same OS process as the BEAM, so any crash, leak, or scheduler stall propagates directly.

### 2.1 — No NIF is tagged for the dirty scheduler (High)

**Location:** [c_src/localize_nif.cpp:908-915](c_src/localize_nif.cpp:908)

```cpp
static ErlNifFunc nif_funcs[] = {
    {"nif_mf2_validate",    1, nif_mf2_validate},
    {"nif_mf2_format",      3, nif_mf2_format},
    {"nif_collation_cmp",  10, nif_collation_cmp},
    {"nif_plural_rule",     4, nif_plural_rule},
    {"nif_number_format",   4, nif_number_format},
    {"nif_unit_format",     4, nif_unit_format}
};
```

The four-field `ErlNifFunc` initialiser omits the `flags` field, so every entry defaults to `0` — regular scheduler. The Erlang scheduler expects a NIF call to complete in **under 1 ms** to keep responsiveness. ICU MessageFormat parsing of a 1 MB MF2 message, an `ucol_strcollIter` of two long strings, or `NumberFormatter` work driven by deeply nested skeleton input can each easily exceed that. While the NIF is busy, the scheduler cannot run any other process bound to it; with N online schedulers, an attacker only needs N concurrent slow calls to halt the node.

**Severity:** **High**. This is the single most consequential operational risk in the codebase, because the latency of ICU operations is *known to be variable*. ICU does not document worst-case complexity for `setPattern` on adversarial MF2 input, and `ucol_strcollIter` on a pathological string (e.g. millions of combining characters) is empirically slow.

**Remediation:** add `ERL_NIF_DIRTY_JOB_CPU_BOUND` to every entry whose work is not provably under 1 ms. The NIF table becomes:

```cpp
static ErlNifFunc nif_funcs[] = {
    {"nif_mf2_validate",    1, nif_mf2_validate, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"nif_mf2_format",      3, nif_mf2_format,   ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"nif_collation_cmp",  10, nif_collation_cmp,ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"nif_plural_rule",     4, nif_plural_rule,  0},
    {"nif_number_format",   4, nif_number_format,ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"nif_unit_format",     4, nif_unit_format,  ERL_NIF_DIRTY_JOB_CPU_BOUND}
};
```

`nif_plural_rule` is short and may be left on the regular scheduler; everything else takes a string and does ICU-internal work whose runtime depends on the input.

### 2.2 — Reorder-codes binary length cast and unbounded `enif_alloc` (High)

**Location:** [c_src/localize_nif.cpp:526-543](c_src/localize_nif.cpp:527)

```cpp
if (reorderBin.size > 0 && reorderBin.size % 4 == 0) {
    int32_t numCodes = (int32_t)(reorderBin.size / 4);
    int32_t* codes = (int32_t*)enif_alloc(sizeof(int32_t) * numCodes);
    /* ... */
}
```

Two issues:

1. **Signed overflow.** `reorderBin.size` is `size_t` (64-bit on the target platforms). Dividing by 4 and casting to `int32_t` silently wraps for binaries above 8 GB. While 8 GB is unrealistic for an `Accept-Language`-shaped input, an attacker with the ability to allocate a large refc binary (e.g. by feeding a long stream into a process before forwarding) can produce one. After overflow, `numCodes` may be negative, `sizeof(int32_t) * numCodes` becomes a huge unsigned value, and `enif_alloc` returns `NULL`; the code does not check the return value (line 529) and dereferences `codes[i]` on line 533, **crashing the BEAM**.
2. **No upper bound on caller-supplied allocation.** Even at smaller sizes, a 1 GB binary causes an attempt to `enif_alloc` 1 GB. The NIF performs no sanity check on `numCodes` against a sensible upper bound (ICU has only ~30 reorder codes; legitimate input is at most a few dozen).

**Severity:** **High**. Easiest exploit is an Erlang-side caller that feeds a large binary and crashes the node. The exploit vector requires reaching `nif_collation_cmp/10` directly — typically only the library reaches it — but if a public Localize collation API forwards a caller-supplied option through to the reorder bytes, this becomes an external vector.

**Remediation:**

* Cap `numCodes` at, say, 256.
* Check the `enif_alloc` return value before use.
* Promote `numCodes` arithmetic through `size_t` and only cast to `int32_t` at the ICU API boundary (after the bounds check).

### 2.3 — Numeric parsing in JSON args without exception guards (Medium)

**Location:** [c_src/localize_nif.cpp:298-316](c_src/localize_nif.cpp:308)

```cpp
std::string val = parse_json_value(json, pos);
/* ... */
if (is_number && has_dot) {
    args[UnicodeString::fromUTF8(key)] = Formattable(std::stod(val));
} else if (is_number) {
    args[UnicodeString::fromUTF8(key)] = Formattable(static_cast<int64_t>(std::stoll(val)));
}
```

`std::stoll` throws `std::out_of_range` for `"99999999999999999999"`, and `std::stod` throws on inputs outside `double` range. The NIF is compiled without `-fno-exceptions` (ICU itself uses exceptions internally), so the throw unwinds through the NIF entry point. Erlang does not understand C++ stack frames; an exception unwinding past `enif_make_*` calls **crashes the BEAM**.

The pre-validation loop at lines 301-306 only enforces digits / `-` / `.`, which is enough to make `stoll` throw on a 100-digit input that passes the loop.

**Severity:** **Medium**. Reachable via `Localize.Nif.mf2_format/3` whenever the JSON args produced by the Elixir wrapper contain a too-large integer or non-finite double. Since the wrapper is at [lib/localize/nif.ex:120](lib/localize/nif.ex:120) and feeds caller-supplied bindings into `:json.encode/1`, an attacker who controls the bindings of an MF2 message can send `999999999999999999999`.

**Remediation:** wrap each `std::stoll` / `std::stod` in a `try { … } catch (const std::exception&) { return enif_make_badarg(env); }` block. Or replace with `std::from_chars`, which reports failure via return code rather than exception.

### 2.4 — Out-of-bounds read in JSON parser on truncated input (Medium)

**Location:** [c_src/localize_nif.cpp:269-319](c_src/localize_nif.cpp:278)

The hand-rolled JSON parser does `if (json[pos] == '}') break;` at line 278 immediately after `skip_ws`, but `skip_ws` only advances `pos` *up to* `json.size()` — it does not signal end-of-input. If the JSON terminates after `{ ` (one byte plus whitespace), `pos` will be at `json.size()` and `json[pos]` reads one byte past the buffer end. `std::string` typically reserves a NUL terminator, so the read does not always crash, but the read is undefined behaviour and may return a stack value depending on optimiser choices.

The same shape repeats at lines 282 and 286.

**Severity:** **Medium**. Not directly exploitable for memory disclosure (the buffer is always on a `std::string`), but it is a real OOB read on attacker input. Worth fixing both to harden and to silence sanitisers.

**Remediation:** add `if (pos >= json.size()) return false;` after every `skip_ws` call, or replace the parser with `:json.decode/1` on the Erlang side and pass already-parsed terms.

### 2.5 — No length cap on caller strings handed to ICU (Medium)

**Location:** [c_src/localize_nif.cpp:331, 374-376, 392, 489-490](c_src/localize_nif.cpp:331)

`get_string` (used in `nif_mf2_validate`, `nif_mf2_format`, `nif_collation_cmp`, etc.) calls `enif_inspect_binary` and copies into a `std::string` with no size cap. A 100 MB MF2 message becomes a 100 MB `std::string`, then a 100 MB `UnicodeString` (UTF-16, so ~200 MB), and ICU's parser walks it on a regular scheduler.

**Severity:** **Medium**. The downstream consequence (scheduler stall and memory pressure) is mitigated by 2.1 if dirty schedulers are adopted. With dirty schedulers, this becomes a memory-only DOS; without them, it's also a node-wide stall.

**Remediation:** establish a per-call input cap (e.g. 64 KB for MF2 messages, 1 MB for collation strings) at the NIF boundary, and reject larger inputs with `enif_make_badarg(env)`. The Elixir wrappers in `lib/localize/nif.ex` should mirror this cap so callers see a clear error rather than a `:badarg`.

### 2.6 — Number format strings parsed with `std::stod` / `std::stoll` (Medium)

**Location:** [c_src/localize_nif.cpp:641, 784, 796, 874](c_src/localize_nif.cpp:641)

`nif_number_format` and `nif_unit_format` accept the number as a string and re-parse it with `std::stod` / `std::stoll`. Same exception-on-bad-input issue as 2.3, plus `std::stod` of a multi-megabyte digit string is itself slow.

**Severity:** **Medium**. Reachable from any public Localize formatting call that hits the NIF path (gated by the `LOCALIZE_NIF` flag).

**Remediation:** as 2.3 — exception guards and a reasonable string-length cap.

### 2.7 — `size_t → uint32_t` truncation in collation iterator setup (Low)

**Location:** [c_src/localize_nif.cpp:489-491](c_src/localize_nif.cpp:489)

```cpp
(uint32_t)binA.size
```

Truncates silently above 4 GB. Realistic exploit requires a 4 GB binary, which is unusual but not impossible on a long-running BEAM with refc binaries.

**Severity:** **Low**. Documented for completeness.

**Remediation:** keep length in `size_t` and only narrow at the ICU API boundary, after asserting against the iterator's documented limit.

### 2.8 — Resource lifetime sanity check (Info)

The collation pool initialises N collators at `on_load` and reuses them through a stack-protected mutex. The pool counts up on `reserve_coll`, but **never refuses a request when the stack is exhausted** — `pData->collators[pData->collStackTop]` with `collStackTop >= numCollators` is an OOB read. Reachable if more concurrent collation calls than schedulers exist (e.g. when the dirty-scheduler fix at 2.1 is added without also resizing the pool).

**Severity:** **Info** today, **Medium** if 2.1 is fixed without also fixing this.

**Remediation:** check `collStackTop < numCollators` under the mutex; either spin-wait, return `:busy`, or grow the pool.

---

## 3. Parser DoS and unbounded input

### 3.1 — `Localize.LanguageTag.parse/1` accepts unbounded input length (Medium)

**Location:** [lib/localize/language_tag.ex:204](lib/localize/language_tag.ex:204) and the NimbleParsec grammar at `lib/localize/language_tag/rfc5646/`.

The function does not impose any length cap on the binary handed to the grammar. RFC 5646 caps each subtag at 8 ASCII characters, but a tag is a `-`-joined sequence of subtags and can theoretically be very long. NimbleParsec processes input linearly, so the runtime cost is `O(n)` rather than super-linear, but combined with finding 1.1 (every parsed subtag becomes an atom) the input length determines the rate at which the atom table fills.

A 10 MB binary that parses successfully (alternating `-aaaaa-bbbbb-…` valid-looking subtags) yields ~1 M new atoms in a single call. **One request fills the atom table.**

**Severity:** **Medium** in isolation, **High** when combined with 1.1 (which is the default state today).

**Remediation:** reject inputs above a sensible cap (e.g. 256 bytes — even the most extravagant well-formed BCP-47 tag fits in well under that). Apply the cap at the outermost `parse/1` and `new/1` entry points before invoking the grammar.

```elixir
def parse(binary) when is_binary(binary) and byte_size(binary) > @max_tag_bytes do
  {:error, Localize.LanguageTagInvalidError.exception(reason: :too_long)}
end
```

### 3.2 — MessageFormat 2 parser uses unbounded `repeat()` with recursive structure (Medium)

**Location:** [lib/localize/message/parser/parser.ex:163-319](lib/localize/message/parser/parser.ex:163)

```elixir
|> repeat(s() |> concat(option_v))      # line 163
|> repeat(s() |> concat(attribute_v))   # line 172
|> repeat(declaration_v |> concat(o())) # line 294
```

NimbleParsec `repeat/1` has no built-in upper bound — it is greedy until the inner parser fails. The MF2 grammar is also recursive: a quoted-pattern can contain expressions that contain placeholders that contain markup that contain quoted-patterns, and so on. Two attack shapes:

1. **Wide.** A message body of `M{$a}{$a}{$a}…{$a}` with N placeholders runs the parser for `O(N)` time — `O(1)` per placeholder, but each one allocates an AST node. The Elixir-side parser is bounded by available heap; the NIF path (`mf2_validate`, `mf2_format`) hands the entire string to ICU, which is opaque.
2. **Deep.** A message body of `{{{{...}}}}` (deeply nested quoted-patterns) allocates a stack of recursion frames per level. NimbleParsec is iterative for `repeat` but recursive for `parsec` references; `pattern → quoted_pattern → pattern → …` is a `parsec` cycle. Deep nesting consumes the BEAM process stack, which on default settings has a hard limit (`max_heap_size`, ~~16 MB by default for the heap, but stack-only growth is bounded by the schedulers' C stack).

**Severity:** **Medium**. The Elixir process would crash on stack overflow before the BEAM does, so the blast radius is one process. But that one process holds the request, and depending on how callers funnel input, the overhead per attack is small.

**Remediation:** apply an outer `byte_size/1` gate (e.g. 64 KB) on the message text in `Localize.Message.parse/1` and similar entry points. Add a per-call recursion-depth counter for the recursive `parsec` references. Both NimbleParsec and the NIF path benefit equally from the outer gate.

### 3.3 — Unit parser has unbounded `-per-` chains (Medium)

**Location:** [lib/localize/unit/parser.ex:144-161](lib/localize/unit/parser.ex:144)

```elixir
|> repeat(ignore(string("-per-")) |> concat(parsec(:product_unit_p)))
```

A unit identifier like `meter-per-second-per-second-per-…` is parsed without any limit on the chain length. Like 3.2 this is `O(n)` linear-time, but unbounded inputs allow an attacker to spend arbitrary CPU per call.

**Severity:** **Medium**. Reachable from `Localize.Unit.new/1` and `Localize.Unit.Parser.parse/1`. Severity becomes high if the parser also atomises its output (it does not — checked in [lib/localize/unit/parser.ex](lib/localize/unit/parser.ex)).

**Remediation:** byte_size cap on input (e.g. 256 bytes; legitimate compound units fit in 60).

### 3.4 — `Localize.Number.parse/2` has no length cap and accepts unbounded Decimal exponent (Medium)

**Location:** [lib/localize/number/parser.ex:100-540+](lib/localize/number/parser.ex:100) and the underlying Decimal parser.

`Localize.Number.parse/2` ultimately delegates to `Decimal.parse/1` for the numeric value. `Decimal` supports arbitrary-precision values, including arbitrary exponent magnitudes. A literal of `"1e9999999999"` produces a `%Decimal{}` whose serialised form is small but whose **arithmetic is unboundedly expensive** — any subsequent multiplication or formatting expands the mantissa to match the exponent.

The library's pre-Decimal regex (line 62-64) tolerates `e[+-]?\d+` with no digit count cap.

**Severity:** **Medium**. The decimal struct itself is small in memory; the DOS surface is downstream operations that materialise the number. `Localize.Number.to_string/2` on `%Decimal{exp: 9_999_999}` will, at minimum, walk the formatted output which is exponent-sized.

**Remediation:** after parsing, validate `abs(decimal.exp) <= @max_exponent` (e.g. 100) before returning. If callers expect huge exponents, expose a separate `parse_unbounded/2` and warn in the docs.

### 3.5 — Format cache is bounded but grows quickly under attack (Medium)

**Location:** [lib/localize/format_cache.ex:96-122](lib/localize/format_cache.ex:96)

```elixir
:ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
```

The cache is `:public` and bounded only by a sweeper running every 10 s. If the format key is caller-controlled (it is — both `lib/localize/datetime/formatter.ex:133` and `lib/localize/number/formatter/decimal.ex:49` use the user-supplied format string as the key), an attacker can:

1. Spam unique format strings to force unbounded compilation of new tokens. The cache grows freely within each 10 s window. At 10 000 RPS with unique formats, the cache reaches ~100 000 entries before the first sweep.
2. After the sweep, the cache is reduced toward `@default_max_entries` (2 000) but the **eviction is biased random**: each candidate key has a 50% chance of being deleted, so the loop may exit before reaching the intended count. Inspect lines 134-142:

   ```elixir
   if :rand.uniform() < 0.5 do
     :ets.delete(@table, key)
     evict_random(next_key, remaining - 1)
   else
     evict_random(next_key, remaining)
   end
   ```

   If `remaining` runs out before `:rand.uniform()` chooses to delete enough keys, the cache stays oversized.
3. Compile-on-miss runs on the calling process; under attack every request pays the compile cost. The compiler is leex/yecc, which is linear, but a 1 KB pathological format string compiled on every request still costs.

Additional subtlety: the cache is `:public`, so any other process in the node can write to or delete from it. In a multi-tenant BEAM that is a noticeable trust assumption.

**Severity:** **Medium**. Memory damage is bounded; CPU damage from compilation churn is the more likely real-world impact.

**Remediation:**

* Make the cache `:protected` and route writes through the gen-server. This costs latency but caps writes at the gen-server's mailbox throughput.
* When an insert would exceed `@default_max_entries`, evict synchronously (LRU or FIFO) instead of relying on the timer.
* Better: **only cache compiled formats whose source string is validated to come from CLDR or developer code, not from the request**. Introduce a `cache: false` option for caller-supplied formats.

---

## 4. Deserialisation, file path handling and code loading

### 4.1 — `binary_to_term/1` without `[:safe]` on locale cache files (High)

**Location:** [lib/localize/locale/provider/cache.ex:101-117](lib/localize/locale/provider/cache.ex:104) and [lib/localize/locale/provider/cache.ex:196-207](lib/localize/locale/provider/cache.ex:201)

```elixir
defp read_and_validate(locale_id, file_path) do
  case File.read(file_path) do
    {:ok, binary} ->
      locale_data = :erlang.binary_to_term(binary)
      # ...
```

`binary_to_term/1` without `:safe` will:

* Resurrect any atom mentioned in the encoded term, allocating new atoms in the global table. A 1 MB ETF crafted to mention 1 M unique atoms instantly crashes the BEAM by atom-table overflow.
* Resurrect funs and pids and references (which generally cannot be exploited for code execution, but can disrupt distribution).

The cache directory used by `read_and_validate/2` is `Localize.Locale.Provider.locale_cache_dir/0`, which is:

```elixir
Application.get_env(:localize, :locale_cache_dir, default_locale_cache_dir())
```

When unset it points to `Application.app_dir(:localize, "priv/localize/locales")` — read-only, bundled, trusted. **When a host application configures `:locale_cache_dir` to a writable directory** (the documented and supported way to enable downloadable locales), the bytes are no longer trusted. The version-mismatch check at line 108 happens **after** `binary_to_term/1` has already created atoms, so it does not stop the attack.

**Severity:** **High** for any deployment that sets `:locale_cache_dir` to a directory writable by anything other than the BEAM owner — a shared `/tmp` mount, a container with a hostile sidecar, a developer machine with another user, etc.

**Remediation:** use `:erlang.binary_to_term(binary, [:safe])`. The flag forbids creation of new atoms, new funs, and new resources. Any locale ETF written by `Localize.Locale.Provider.Cache.store/2` only references atoms defined at compile time, so `[:safe]` does not break legitimate use.

```elixir
locale_data = :erlang.binary_to_term(binary, [:safe])
```

Catch `ArgumentError` from the call and return the existing `LocaleNotFoundInCacheError` shape. Do the same fix at line 201 (`stale?/1`).

### 4.2 — `binary_to_term/1` without `[:safe]` on bundled `priv/*.etf` files (Low)

**Location:** [lib/localize/supplemental_data.ex:17, 29, 41](lib/localize/supplemental_data.ex:17), [lib/localize/collation/table.ex:353](lib/localize/collation/table.ex:353), [lib/localize/collation/unicode.ex:44](lib/localize/collation/unicode.ex:44), [lib/localize/unit/data.ex:19](lib/localize/unit/data.ex:19), [lib/localize/number/system.ex:664](lib/localize/number/system.ex:664), [lib/localize/datetime/format/match.ex:53](lib/localize/datetime/format/match.ex:53)

These read bytes from `Application.app_dir(:localize, "priv/...")` and decode them. The bundled `.etf` files ship with the package and are produced by the build pipeline; the bytes are trusted in the same sense that the `.beam` files are. If an attacker has write access to `priv/`, they can inject arbitrary atoms — but at that point they can also replace the `.beam` files, so the deserialisation vector is not the weak link.

**Severity:** **Low**. Document for completeness.

**Remediation:** still pass `[:safe]`. The bundled files do not contain anything `[:safe]` rejects, and the change inoculates against the day someone moves to dynamic loading.

### 4.3 — `Localize.Unit.CustomRegistry.load_file/1` evaluates Elixir from disk (Low — by design)

**Location:** [lib/localize/unit/custom_registry.ex:158-189](lib/localize/unit/custom_registry.ex:158)

```elixir
{definitions, _bindings} = Code.eval_file(expanded)
```

Documented at [lib/localize/unit/custom_registry.ex:140-144](lib/localize/unit/custom_registry.ex:140) with an explicit warning:

> This function uses `Code.eval_file/1` to evaluate the given file, which executes arbitrary Elixir code. Only load files from trusted sources. Never call this function with unsanitised user input or paths derived from external data.

That warning is appropriate. The function is correctly named (it is a *custom* registry, intended for operator-loaded units). The risk is operator-shaped, not attacker-shaped.

**Severity:** **Low (by design)**.

**Remediation:** none required at the API level. Two complementary hardenings worth considering:

* Reject the call when running in `:prod` *unless* `:localize, :allow_runtime_unit_files` is `true`. Requiring an explicit flag ensures a runaway feature switch in a deployment cannot accidentally surface this.
* Validate `expanded` against an allowlist of directories before reading. Defence in depth.

### 4.4 — File path construction is safe (Info)

`Localize.SupplementalData` and the locale cache module both build paths via `Path.join/2` with constants on one side. The locale-id portion of the path passes through `Localize.Locale.Provider.locale_file_name/1`, which converts an atom to `"<atom>.etf"`. Atoms cannot contain path separators, so traversal via `..` is not reachable. Confirmed by inspection of the `path/1` function and the surrounding code; no finding.

### 4.5 — Public ETS tables (Info)

The `:localize_format_cache` (covered in 3.5) and `:localize_locale_cache` (created by the application supervisor) are both `:public`. Public tables let any process in the BEAM write to them. In a multi-tenant setup, this means library A and library B share the cache and can corrupt each other's state. This is conventional for caches but worth flagging.

**Remediation:** consider switching both to `:protected` and routing writes through their owner gen-servers. Not urgent but tightens the trust model.

### 4.6 — Regex usage is safe (Info)

`rg -n '~r'` returns a small set of regexes, all of which are simple character classes (`~r/{[0-9]}/`, `~r/[A-Z]+/`, etc.) without nested quantifiers. No catastrophic-backtracking surface was identified. The grammars that do the heavy lifting (RFC 5646, MF2, decimal formats, RBNF) are all built with NimbleParsec / leex / yecc, none of which exhibit ReDoS-shaped behaviour.

**Severity:** **Info** — no finding.

---

## 5. Remediation summary and prioritisation

The findings cluster into three operational classes. Tackling them in this order produces the largest reduction in risk per unit of work.

### Tier 1 — fix before next release (atom-exhaustion class)

Atom-exhaustion is the most consequential class because **a single malicious request fills the global atom table and crashes the entire BEAM**. Every issue below has the same root cause: the codebase has internal helpers named `safe_to_atom` / `to_atom_safe` whose implementations fall through to `String.to_atom/1` on miss, instead of returning `nil` or the raw string. Fixing the helpers fixes most of the surface.

1. Make `Localize.Utils.Helpers.existing_atom/1` the single canonical helper. It already returns `nil` on miss ([lib/localize/utils/helpers.ex:73](lib/localize/utils/helpers.ex:73)).
2. Rewrite the local `safe_to_atom` / `to_atom_safe` definitions in [lib/localize/gettext/interpolation.ex:131](lib/localize/gettext/interpolation.ex:131) and [lib/localize/locale/locale_display/t.ex:342](lib/localize/locale/locale_display/t.ex:342) to drop the `|| String.to_atom(name)` fallback. The call sites should be audited and updated to handle the `nil` case explicitly.
3. In [lib/localize/language_tag/parser.ex:75-85](lib/localize/language_tag/parser.ex:75), only emit an atom for a subtag that is present in the validity set. Every other case should return `{:error, _}` from the parse step.
4. In [lib/localize/locale.ex:639, 644-645](lib/localize/locale.ex:644), use `Helpers.existing_atom/1` and propagate `nil` / `{:error, _}` rather than coerce to a fresh atom.
5. In [lib/localize/currency.ex:1004-1009](lib/localize/currency.ex:1007), reorder so the atom is only created for known-existing currency codes.
6. In [lib/localize/locale/locale_display/u.ex:355-356](lib/localize/locale/locale_display/u.ex:355), route both `region_key` and `city_key` through `safe_to_atom` (the *correctly-implemented* one in this same file at line 148).
7. In [lib/localize/locale/provider/cache.ex:104, 201](lib/localize/locale/provider/cache.ex:104), pass `[:safe]` to `binary_to_term/1`.

Each fix is small. Add unit tests that pass adversarial input — e.g. a fuzz test that calls `Localize.LanguageTag.parse/1` with random 6-letter strings and asserts that the atom count does not grow.

### Tier 2 — fix in the same release window (DoS class)

These do not crash the node but allow a single caller to consume disproportionate CPU or memory. Fixing them is straightforward and adds boundary discipline that the library currently lacks.

8. Tag the NIF entries with `ERL_NIF_DIRTY_JOB_CPU_BOUND` ([c_src/localize_nif.cpp:908](c_src/localize_nif.cpp:908)). Resize the collation pool to match `enif_dirty_schedulers_online()` rather than `enif_schedulers_online()` once dirty schedulers are in use, **and** add a busy/wait-or-fail check in `reserve_coll`.
9. Add input-length caps at the public-API boundary. Recommended starting points:
   * `Localize.LanguageTag.parse/1` — 256 bytes.
   * `Localize.Message.parse/1` — 64 KB.
   * `Localize.Unit.parse/1` — 256 bytes.
   * `Localize.Number.parse/2` — 1 KB digits, plus a Decimal exponent cap (e.g. ±100).
   * NIF entry points — match the Elixir-side caps and reject larger inputs at the C++ boundary as well.
10. Format cache:
    * Switch to synchronous LRU eviction on insert when the size is at the cap.
    * Make the table `:protected` and route writes through the owner gen-server.
    * Expose a `cache: false` option to the public formatting APIs and recommend it for caller-supplied formats.
11. NIF JSON parser:
    * Wrap every `std::stoll` / `std::stod` in a try/catch returning `enif_make_badarg(env)`.
    * Add `pos < json.size()` guards after every `skip_ws` call.
    * Or — simpler — replace the C++ JSON parser with a pre-decoded term passed from the Elixir side.

### Tier 3 — defence-in-depth and follow-ups

12. Cap `numCodes` in the collation reorder branch ([c_src/localize_nif.cpp:527](c_src/localize_nif.cpp:527)) and check the `enif_alloc` return value before use.
13. Pass `[:safe]` to `binary_to_term/1` on bundled `.etf` files ([lib/localize/supplemental_data.ex](lib/localize/supplemental_data.ex) and friends). Bundled files are trusted today, but `[:safe]` future-proofs the code against a move to runtime-fetched data.
14. Reconsider the public/protected status of `:localize_format_cache` and `:localize_locale_cache`.
15. Document the `Localize.Unit.CustomRegistry.load_file/1` warning more visibly — for instance, refuse to evaluate the file in production unless an explicit `:localize, :allow_runtime_unit_files` flag is set.

### What was not found

The audit did **not** identify:

* Catastrophic-backtracking regexes. The runtime regex surface is small and all patterns are simple character classes.
* Path-traversal vectors. File paths are constructed with constants and validated locale atoms.
* `Code.eval_string/1` or `Macro.expand/2` on caller input.
* Memory-corruption bugs in the NIF beyond the integer-overflow paths described above. Resource lifetimes look correct: `ucol_open` / `ucol_close` are paired, `MessageFormatter::Builder` is stack-allocated, `UnicodeString` and `std::string` manage their own buffers. The collation pool is per-scheduler with mutex protection.
* Use of `:erlang.binary_to_atom(_, :utf8)` or `List.to_atom/1` on caller input outside the sites listed in §1.
* Use of `:os.cmd/1`, `System.cmd/2`, `Port.open/2`, or any other shell-execution primitive.
* Predictable random-number use in security-sensitive paths.

### Suggested test additions

Each of the high-severity findings deserves an adversarial-input regression test. Concretely:

* A property test for `Localize.LanguageTag.parse/1` that runs `:erlang.system_info(:atom_count)` before and after a batch of random parses and asserts equality.
* A property test for `Localize.Currency.currencies_for/2` doing the same.
* An NIF stress test that calls `nif_collation_cmp/10` with a deliberately too-large reorder binary and asserts a clean `:badarg` rather than a node crash.
* A unit test that places a malicious ETF (one that mentions a never-seen atom name) in the locale cache directory and verifies that loading it raises rather than creating the atom.

---

## Audit complete.

This document covers the full runtime API surface of `localize` v0.28.0. Everything material that the auditor identified is in scope. Areas explicitly out of scope: build-time CLDR ingestion (`data/`), the Mix tasks, and the bundled `priv/*.etf` artefacts as a supply-chain concern (which is a packaging issue, not a library code issue).

