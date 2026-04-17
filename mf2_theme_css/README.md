# MF2 highlighter themes

Drop-in CSS stylesheets for output produced by `Localize.Message.to_html/2`. Each file is a port of a theme from [`makeup_elixir`](https://hex.pm/packages/makeup) onto the `.mf2-*` class namespace used by the MF2 highlighter, so a page that already uses a Makeup theme for Elixir syntax can match it for MF2 with one extra `<link>`.

These files are **not shipped in the Hex package** — they live here as reference material and can be copied directly into consuming applications.

## Usage

Pick a theme and serve the file. The stylesheet targets:

* `.mf2-highlight` — the `<pre>` wrapper emitted when `to_html/2` is called with `standalone: true`.

* `.mf2-text`, `.mf2-punctuation`, `.mf2-name_variable`, `.mf2-name_function`, `.mf2-name_builtin`, `.mf2-name_tag`, `.mf2-name_attribute`, `.mf2-name_label`, `.mf2-string`, `.mf2-number_integer`, `.mf2-number_float`, `.mf2-escape`, `.mf2-keyword_constant` — the individual token spans.

```elixir
{:ok, html} = Localize.Message.to_html(message, standalone: true)
# Render `html` into a page that includes, e.g. `monokai.css`.
```

For a custom class prefix (`class_prefix: "xx-"`), run the CSS through a find-and-replace on `.mf2-` → `.xx-` before serving.

## Available themes

Light: `abap`, `algol_nu`, `autumn`, `borland`, `bw`, `colorful`, `default`, `emacs`, `friendly`, `igor`, `lovelace`, `manni`, `murphy`, `paraiso_light`, `pastie`, `perldoc`, `rainbow_dash`, `samba`, `tango`, `trac`, `vs`, `xcode`.

Dark: `fruity`, `monokai`, `native`, `paraiso_dark`, `rrt`, `vim`.

Monochrome: `algol`.

## Regenerating

These files are produced by `scripts/generate_mf2_themes.exs`, which reads the upstream Makeup theme sources and rewrites them onto the MF2 class taxonomy. To refresh:

```bash
elixir scripts/generate_mf2_themes.exs
```

The script expects the `makeup` source checkout at a fixed path; adjust `source_dir` inside the script if your checkout lives elsewhere.

## Mapping

The MF2 taxonomy is narrower than Pygments'. Each MF2 class looks up the first match in a prioritised list of Makeup classes:

| MF2 class            | Makeup lookup order                               |
| -------------------- | ------------------------------------------------- |
| `mf2-text`           | `text` → `name` → `generic`                       |
| `mf2-punctuation`    | `punctuation` → `operator`                        |
| `mf2-name_variable`  | `name_variable` → `name_variable_instance` → `name` |
| `mf2-name_function`  | `name_function` → `name_other`                    |
| `mf2-name_builtin`   | `name_builtin` → `keyword_namespace` → `keyword`  |
| `mf2-name_tag`       | `name_tag` → `keyword`                            |
| `mf2-name_attribute` | `name_attribute` → `name_decorator`               |
| `mf2-name_label`     | `name_label` → `name_attribute`                   |
| `mf2-string`         | `string` → `string_double` → `literal`            |
| `mf2-number_integer` | `number_integer` → `number` → `literal`           |
| `mf2-number_float`   | `number_float` → `number` → `literal`             |
| `mf2-escape`         | `string_escape` → `literal` → `keyword`           |
| `mf2-keyword_constant` | `keyword_constant` → `keyword` → `name_tag`     |

If none match, the class gets an empty rule (browser default — typically inherits from `.mf2-highlight`). Because different themes make different distinctions, a few variables may inherit from the base `name` colour rather than getting a dedicated accent — edit the individual CSS file if you want more differentiation.
