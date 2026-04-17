# Generate MF2 CSS themes by porting makeup_elixir Pygments themes onto the
# `.mf2-*` class namespace. Reads theme files from the `cldr_strftime`
# sibling checkout (which has `makeup` as a dep) and writes a CSS file per
# theme into `mf2_theme_css/`.
#
# Run with:
#   elixir scripts/generate_mf2_themes.exs

source_dir =
  "/System/Volumes/Data/Users/kip/Development/cldr_strftime/deps/makeup/lib/makeup/styles/html/pygments"

out_dir = Path.join(File.cwd!(), "mf2_theme_css")
File.mkdir_p!(out_dir)

# Mapping from MF2 class (our taxonomy) to a prioritised list of Makeup
# class names to probe. First match wins.
mf2_class_map = [
  mf2_text: [:text, :name, :generic],
  mf2_punctuation: [:punctuation, :operator],
  mf2_name_variable: [:name_variable, :name_variable_instance, :name],
  mf2_name_function: [:name_function, :name_other],
  mf2_name_builtin: [:name_builtin, :keyword_namespace, :keyword],
  mf2_name_tag: [:name_tag, :keyword],
  mf2_name_attribute: [:name_attribute, :name_decorator],
  mf2_name_label: [:name_label, :name_attribute],
  mf2_string: [:string, :string_double, :literal],
  mf2_number_integer: [:number_integer, :number, :literal],
  mf2_number_float: [:number_float, :number, :literal],
  mf2_escape: [:string_escape, :literal, :keyword],
  mf2_keyword_constant: [:keyword_constant, :keyword, :name_tag]
]

# Parse a Makeup style string (e.g. "bold #204a87", "italic #8f5902",
# "#19177C", "noitalic #BC7A00") into a CSS declaration block.
parse_style = fn string ->
  tokens = String.split(string, ~r/\s+/, trim: true)

  {color, weight, style, extras} =
    Enum.reduce(tokens, {nil, nil, nil, []}, fn token, {color, weight, style, extras} ->
      cond do
        token == "bold" ->
          {color, "bold", style, extras}

        token == "nobold" ->
          {color, "normal", style, extras}

        token == "italic" ->
          {color, weight, "italic", extras}

        token == "noitalic" ->
          {color, weight, "normal", extras}

        token == "underline" ->
          {color, weight, style, ["text-decoration: underline" | extras]}

        String.starts_with?(token, "#") ->
          {token, weight, style, extras}

        String.starts_with?(token, "bg:") ->
          {color, weight, style,
           ["background-color: #{String.replace_prefix(token, "bg:", "")}" | extras]}

        String.starts_with?(token, "border:") ->
          {color, weight, style,
           ["border: 1px solid #{String.replace_prefix(token, "border:", "")}" | extras]}

        true ->
          {color, weight, style, extras}
      end
    end)

  [
    color && "color: #{color}",
    weight && "font-weight: #{weight}",
    style && "font-style: #{style}"
    | extras
  ]
  |> Enum.filter(& &1)
  |> Enum.map(&"  #{&1};")
  |> Enum.join("\n")
end

# Regex-extract `@styles %{...}` body and metadata (short_name, long_name,
# background_color, highlight_color) from a theme source file.
parse_theme = fn path ->
  source = File.read!(path)

  # The @styles map. Match from `@styles %{` to the matching `}`.
  [_, styles_body] = Regex.run(~r/@styles\s+%\{(.*?)\n\s*\}\s*\n/s, source)

  style_pairs =
    Regex.scan(~r/:([a-z_]+)\s*=>\s*"([^"]+)"/, styles_body)
    |> Map.new(fn [_, k, v] -> {String.to_atom(k), v} end)

  short_name =
    Regex.run(~r/short_name:\s*"([^"]+)"/, source)
    |> case do
      [_, n] -> n
      _ -> Path.basename(path, ".ex")
    end

  long_name =
    Regex.run(~r/long_name:\s*"([^"]+)"/, source)
    |> case do
      [_, n] -> n
      _ -> short_name
    end

  background =
    Regex.run(~r/background_color:\s*"([^"]+)"/, source)
    |> case do
      [_, c] -> c
      _ -> nil
    end

  highlight =
    Regex.run(~r/highlight_color:\s*"([^"]+)"/, source)
    |> case do
      [_, c] -> c
      _ -> nil
    end

  %{
    short_name: short_name,
    long_name: long_name,
    background: background,
    highlight: highlight,
    styles: style_pairs
  }
end

# Build CSS text for one theme.
render_css = fn theme ->
  styles = theme.styles

  rules =
    Enum.map(mf2_class_map, fn {mf2_class, candidates} ->
      match = Enum.find_value(candidates, fn key -> Map.get(styles, key) end)

      selector =
        "." <> (mf2_class |> Atom.to_string() |> String.replace("mf2_", "mf2-"))

      case match do
        nil ->
          "#{selector} {}"

        value ->
          "#{selector} {\n#{parse_style.(value)}\n}"
      end
    end)

  wrapper_rules =
    [
      ".mf2-highlight {",
      theme.background && "  background-color: #{theme.background};",
      "  color: #{Map.get(styles, :text, "inherit")};",
      "  padding: 0.75em 1em;",
      "  border-radius: 4px;",
      "  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;",
      "  overflow-x: auto;",
      "}"
    ]
    |> Enum.filter(& &1)
    |> Enum.join("\n")

  header = """
  /*
   * MF2 highlighter theme: #{theme.long_name}
   *
   * Ported from Makeup (`makeup_elixir`) theme "#{theme.short_name}".
   * Apply to output from `Localize.Message.to_html/2`.
   *
   * Usage:
   *   {:ok, html} = Localize.Message.to_html(message, standalone: true)
   *
   * The `:standalone` option wraps the tokens in
   * `<pre class="mf2-highlight"><code>...</code></pre>`; this stylesheet
   * targets that wrapper plus each `.mf2-<class>` span inside it.
   */
  """

  [header, wrapper_rules, "" | rules] |> Enum.join("\n\n") |> String.trim_trailing()
end

# --- Run ---

theme_files =
  source_dir
  |> File.ls!()
  |> Enum.filter(&String.ends_with?(&1, ".ex"))
  |> Enum.sort()

for filename <- theme_files do
  theme = parse_theme.(Path.join(source_dir, filename))
  css = render_css.(theme)
  out_path = Path.join(out_dir, "#{theme.short_name}.css")
  File.write!(out_path, css <> "\n")
  IO.puts("wrote #{out_path}")
end

IO.puts("\n#{length(theme_files)} themes written to #{out_dir}")
