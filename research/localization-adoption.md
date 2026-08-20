# Do real applications localize numbers and dates?

**Measured 2026-08-20.** Claim under test, made in a presentation: *most applications are not localized — Java, C/C++ and Python apps typically use native language facilities rather than ICU4J/ICU4C.*

## Verdict

**The conclusion holds. One premise does not.**

Java is the wrong example. Since JDK 9, [JEP 252](https://openjdk.org/jeps/252) makes CLDR the *default* locale data provider, so `java.text.NumberFormat` and `java.time.format.DateTimeFormatter` are CLDR-backed with no configuration and no dependency. Saying Java apps use "native, non-localized libraries" is refutable in one command.

But the adoption data rescues the conclusion, and sharpens it:

> The problem is not missing libraries. It is that the localized path is never the default path.

Java proves this better than any language where the libraries are absent. The platform is fully CLDR-backed and free, and developers still choose fixed patterns over localized ones **64 to 1**.

## Part 1 — what each language does when you do the obvious thing

Run on macOS 15.6.1, system locale `en-AU`, formatting `1234567.89` and `2026-03-22 14:30`. Full transcript in [§Reproduction](#reproduction).

| Language | The idiomatic call | Output | Localized? |
|---|---|---|---|
| Python | `f"{n:,.2f}"` | `1,234,567.89` | ✗ hard-coded US |
| Python | `format(n, ",.2f")` | `1,234,567.89` | ✗ hard-coded US |
| Python | `d.strftime("%x %X")` | `03/22/26 14:30:00` | ✗ C locale |
| C | `printf("%f", n)` | `1234567.890000` | ✗ |
| C | `printf("%'f", n)` *without* `setlocale` | `1234567.890000` | ✗ grouping flag silently does nothing |
| C | `strftime("%x %X")` *without* `setlocale` | `03/22/26 14:30:00` | ✗ |
| JavaScript | `n.toString()` / `` `${n}` `` | `1234567.89` | ✗ |
| JavaScript | `n.toLocaleString()` | `1,234,567.89` | ✓ ICU, reads OS locale |
| **Java** | `NumberFormat.getInstance()` | `1,234,567.89` | ✓ CLDR, read `en_AU` off the OS |
| **Java** | `String.format("%,.2f", n)` | `1,234,567.89` | ✓ uses default Locale |
| **Java** | `DateTimeFormatter.ofLocalizedDateTime(MEDIUM)` | `22 Mar 2026, 2:30:00 pm` | ✓ CLDR |
| Java | `"" + n`, `String.valueOf(n)` | `1234567.89` | ✗ |

Two observations worth keeping.

**C's `%'` flag is a trap.** The apostrophe flag requests digit grouping, and without a prior `setlocale(LC_ALL, "")` it produces *no grouping at all* rather than an error. The code looks localized and is not.

**Java's data depth is real, not nominal.** Asked for `ar-EG`, the JDK returns `١٬٢٣٤٬٥٦٧٫٨٩` — Arabic-Indic digits with the correct separators. This is not a stub; it is CLDR.

The gap between the two halves of the Java rows is the whole argument: the same runtime gives a localized answer or an unlocalized one depending on which method the developer reaches for, and nothing in the language nudges them toward the first.

## Part 2 — which path do developers actually take?

GitHub code search, file counts, retrieved 2026-08-20. Read these as ratios, not populations — see [§Limits](#limits).

### Java — the localized API exists and is bypassed

| Construct | Files | |
|---|---:|---|
| `DateTimeFormatter.ofPattern` | 489,472 | fixed pattern, not localized |
| `DateTimeFormatter.ofLocalizedDate` | 7,680 | localized |
| `new SimpleDateFormat("yyyy-MM-dd")` | 151,040 | fixed pattern |
| `NumberFormat.getInstance()` | 46,720 | localized |
| `NumberFormat.getInstance(Locale.US)` | 4,848 | pinned to one locale |
| `Locale.US` anywhere | 460,288 | pinned to one locale |
| `String.valueOf` | 3,637,248 | no formatting at all |

**Fixed date patterns outnumber localized ones 64:1.** Hard-coded `Locale.US` outnumbers all localized `NumberFormat.getInstance()` use **10:1**.

### Python — the worst case

| Construct | Files | |
|---|---:|---|
| `from babel …` | 54,016 | CLDR-backed |
| `import icu` (PyICU) | 7,456 | ICU-backed |
| `locale.setlocale` | 217,088 | POSIX locale |
| `strftime("%Y-%m-%d")` | 706,560 | fixed pattern |
| `strftime` (any) | 9,043,968 | pattern-based |
| f-strings (any) | 38,010,880 | never localized |

**Everything CLDR- or ICU-backed combined (~61,500) is 0.7% of `strftime` usage alone.** A single fixed pattern, `"%Y-%m-%d"`, appears 11× more often than `babel` and `PyICU` put together.

Python's `locale` module is the only localized formatting in the standard library, and it is process-global and not thread-safe — which is why library authors avoid it and applications rarely reach for it.

### C / C++ — where "not localized" is literally true

| Construct | Files | |
|---|---:|---|
| `#include <unicode/…>` (C) | 16,672 | ICU4C, any use |
| `#include <unicode/…>` (C++) | 34,496 | ICU4C, any use |
| `setlocale` (C) | 375,296 | POSIX locale |
| `strftime` (C) | 323,584 | pattern-based |
| `std::locale` (C++) | 443,392 | POSIX-ish |
| `printf` (C) | 33,947,648 | never localized by default |

**ICU4C appears in ~51,000 files against 33.9M for `printf` — 663:1.** Even against the POSIX locale facilities, which are themselves weak, ICU is outnumbered roughly 15:1.

### JavaScript — the best case, and why

| Construct | Files | |
|---|---:|---|
| `toLocaleString` | 2,899,968 | ICU-backed |
| `toFixed(` | 6,651,904 | never localized |

**2.3:1 against** — an order of magnitude better than any other language measured. The difference is not developer virtue: `Intl` ships in the runtime, needs no dependency, no build flag and no `setlocale`, and `toLocaleString()` is shorter to type than the alternative.

## What this supports

1. **"Most applications are not localized" — supported.** In every language measured, the unlocalized construct outnumbers the localized one, from 2.3:1 at best to 663:1 at worst.

2. **"They use native libraries instead of ICU" — supported for C/C++ and Python, false for Java.** Java's native library *is* ICU-derived. Use C/C++ as the example if the point is absent capability.

3. **A hypothesis, clearly labelled as such.** JavaScript looks like a natural experiment: same developers under the same deadlines, but localization is one method call away with no dependency — and the ratio improves by two orders of magnitude over C. That invites the conclusion that *the binding constraint is ergonomics and defaults, not capability*.

That conclusion is **not established by this data**, and it should not be presented as if it were. See [§The ergonomics hypothesis](#the-ergonomics-hypothesis).

## The ergonomics hypothesis

> If the localized path were the path of least resistance, developers would take it.

This is an inference drawn from the data above, not a finding of it. The JavaScript comparison is badly confounded:

* **Different exposure.** Web front-ends face international users far more often than a C daemon does. JS developers may localize more because they *need* to, not because it is easier.
* **Different populations.** The people writing JavaScript and the people writing C are largely different, with different training and norms.
* **Different eras.** `Intl` reached broad availability years after `printf`. The comparison mixes API design with vintage.
* **Different denominators.** `toFixed(` is not the only unlocalized way to render a number in JS, so the 2.3:1 ratio flatters the localized side.

Testing it properly needs a controlled experiment — same task, same population, APIs varying only in ergonomics — not repository counts.

### What the literature actually says

There is no study I could find that tests this for internationalization directly. The closest evidence is in two adjacent areas.

**Usable security is the strong analogue.** The question "why don't developers do the correct thing when a correct API exists?" has been studied properly there. Acar et al., [*Comparing the Usability of Cryptographic APIs*](https://ieeexplore.ieee.org/document/7958576/) (IEEE S&P 2017), ran 256 Python developers across five crypto libraries. It establishes that **API design measurably changes outcomes** — which supports the general shape of the hypothesis.

But it complicates the simple version of it. Their results indicate that *simplicity alone is not sufficient*: overly simple APIs produced functional failures, while comprehensive documentation improved functional correctness yet sometimes led to less secure implementations. Specific domain knowledge predicted success better than general programming experience did.

The honest read for our purposes: **"make it easy and they will do it right" is too glib.** Ergonomics matters, but the security literature suggests the mechanism is more like *make the correct thing possible to discover, hard to get wrong, and adequately documented* — three properties, not one. A newer treatment in the same tradition is [*When Security Meets Usability: An Empirical Investigation of Post-Quantum Cryptography APIs*](https://www.ndss-symposium.org/ndss-paper/when-security-meets-usability-an-empirical-investigation-of-post-quantum-cryptography-apis/) (2026).

**i18n research exists, but asks a different question.** Alameer and Halfond, *An Empirical Study of Internationalization Failures in the Web* (ICSME 2016) — [local copy](alameer-halfond-2016-internationalization-failures-in-the-web.pdf), [source](https://viterbi-web.usc.edu/~halfond/papers/alameer16icsme.pdf) — analysed **449 real-world internationalized webpages** and report that "a high percentage of them contained internationalization related problems", with failure prevalence correlating with specific languages and frameworks. Note the population: pages that had *already* been internationalized. It measures i18n quality, not i18n adoption — so it does not speak to our claim directly, but it does establish that doing i18n and doing it correctly are different things.

A [systematic mapping study on l10n and i18n testing](https://www.sciencedirect.com/science/article/pii/S0950584926002478) (2026) covers the testing side and notes that some organisations do not test from an i18n perspective at all, manually or automatically.

### Where that leaves the argument

Use the adoption ratios as the finding — they are solid. Present the ergonomics explanation as a hypothesis with an honest caveat, and it is more persuasive for being offered that way than as a claim the data cannot carry. If it needs to be stronger than that, it needs an experiment: two cohorts, one task, APIs differing only in which path is the default.

## Limits

State these whenever the numbers are used publicly.

* GitHub code search counts **files, not applications**. A monorepo with a thousand call sites and a gist with one both contribute.
* It is biased toward open source, and toward whatever GitHub indexes. Proprietary applications — where most localization requirements actually live — are invisible.
* Vendored dependencies, generated code, tests and examples all count.
* **Presence is not use.** A file containing `toLocaleString` may never render it to a user; a file containing `printf` may be printing a debug line.
* The absolute numbers move with GitHub's index. The ratios are the durable finding.
* Language defaults (Part 1) are exact and reproducible; adoption (Part 2) is directional evidence.

## Reproduction

Language defaults, verbatim:

```bash
python3 -c 'import datetime,locale; n=1234567.89; d=datetime.datetime(2026,3,22,14,30); print(f"{n:,.2f}", d.strftime("%x %X"))'
```

```bash
node -e 'const n=1234567.89; console.log(n.toString(), n.toLocaleString(), n.toLocaleString("de-DE"))'
```

Java — note this reads the OS locale, so the output depends on the machine:

```bash
cat > /tmp/Loc.java <<'EOF'
import java.text.NumberFormat; import java.time.*; import java.time.format.*; import java.util.Locale;
public class Loc { public static void main(String[] a) {
  double n = 1234567.89; LocalDateTime d = LocalDateTime.of(2026,3,22,14,30);
  System.out.println(Locale.getDefault());
  System.out.println(NumberFormat.getInstance().format(n));
  System.out.println(d.format(DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM)));
  System.out.println(NumberFormat.getInstance(Locale.forLanguageTag("ar-EG")).format(n));
}}
EOF
cd /tmp && javac Loc.java && java Loc
```

Adoption counts, one per construct:

```bash
gh api -X GET search/code -f q='"DateTimeFormatter.ofPattern" language:java' --jq '.total_count'
```

GitHub's code search API is limited to 10 requests per minute; a full sweep needs pacing.
