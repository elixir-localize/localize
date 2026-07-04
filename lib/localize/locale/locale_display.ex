defmodule Localize.Locale.LocaleDisplay do
  @moduledoc """
  Implements the CLDR locale display name algorithm to format
  locale identifiers for presentation.

  This module produces localized, human-readable display names
  for locale identifiers. For example, `"en-US"` can be displayed
  as `"English (United States)"` or `"American English"` depending
  on the display mode.

  """

  @basic_tag_order [:language, :script, :territory, :language_variants]
  @reinstate_subtags [:territory, :script]

  @type display_options :: [
          {:language_display, :standard | :dialect},
          {:prefer, atom()},
          {:locale, atom() | String.t() | Localize.LanguageTag.t()}
        ]

  @doc """
  Returns a localized display name for a locale.

  ### Arguments

  * `language_tag` is a `t:Localize.LanguageTag.t/0`, a locale
    name string, or a locale atom.

  * `options` is a keyword list of options.

  ### Options

  * `:language_display` determines if a language is displayed
    in `:standard` format (the default) or `:dialect` format.

  * `:prefer` signals the preferred name for a subtag when
    there are alternatives. The default is `:standard`.

  * `:locale` is the locale in which to display the name.
    The default is `:en`.

  ### Returns

  * `{:ok, string}` representing a presentation-ready name.

  * `{:error, exception}` if the name cannot be produced.

  ### Examples

      iex> Localize.Locale.LocaleDisplay.display_name("en")
      {:ok, "English"}

      iex> Localize.Locale.LocaleDisplay.display_name("en-US")
      {:ok, "English (United States)"}

      iex> Localize.Locale.LocaleDisplay.display_name("en-US", language_display: :dialect)
      {:ok, "American English"}

      iex> Localize.Locale.LocaleDisplay.display_name("nl-BE", language_display: :dialect)
      {:ok, "Flemish"}

  """
  @spec display_name(Localize.LanguageTag.t() | String.t() | atom(), display_options()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def display_name(locale, options \\ []) do
    # Validate/normalize every input through the one canonical path
    # (`Localize.validate_locale/1`), then drive the display off the
    # canonical-syntax subtags carried in `canonical_locale_id`. This
    # keeps a string and an equivalent (maximized) `%LanguageTag{}`
    # rendering identically and prevents likely-subtags from leaking into
    # the output — bare `"en"` is "English", not "English (United States)".
    with {:ok, validated} <- Localize.validate_locale(locale) do
      validated
      |> canonical_display_tag()
      |> do_display_name(options)
    end
  end

  # Reduce the maximized subtag fields to the canonical-syntax form held
  # in `canonical_locale_id` (the caller's explicit request), keeping the
  # validated tag's resolved `-u-`/`-t-` extensions and private use.
  defp canonical_display_tag(%Localize.LanguageTag{canonical_locale_id: id} = validated)
       when is_binary(id) do
    case Localize.LanguageTag.parse(id) do
      {:ok,
       %Localize.LanguageTag{
         language: language,
         script: script,
         territory: territory,
         language_variants: variants
       }} ->
        %{
          validated
          | language: language,
            script: script,
            territory: territory,
            language_variants: variants
        }

      _ ->
        validated
    end
  end

  defp canonical_display_tag(%Localize.LanguageTag{} = validated), do: validated

  defp do_display_name(%Localize.LanguageTag{} = language_tag, options) do
    locale_id = resolve_locale_id(options)
    prefer = Keyword.get(options, :prefer, :standard)
    prefer = if prefer == :default, do: :standard, else: prefer
    standard_or_dialect = Keyword.get(options, :language_display, :standard)

    with :ok <- validate_language_display(standard_or_dialect),
         {:ok, display_names} <- load_display_names(locale_id),
         {:ok, matched_tags, language_name} <-
           language_name(language_tag, display_names, prefer, standard_or_dialect) do
      language_tag = merge_extensions_and_private_use(language_tag)

      subtag_names =
        language_tag
        |> subtag_names(@basic_tag_order -- matched_tags, prefer, display_names)
        |> List.flatten()
        |> Enum.map(&replace_nested_brackets(&1, display_names))
        |> join_subtags(display_names)

      extension_names =
        language_tag
        |> extension_display_names(locale_id, display_names, options)
        |> join_subtags(display_names)

      {:ok, format_display_name(language_name, subtag_names, extension_names, display_names)}
    end
  end

  @doc """
  Same as `display_name/2` but raises on error.

  ### Arguments

  * `language_tag` is a `t:Localize.LanguageTag.t/0`, a locale
    name string, or a locale atom.

  * `options` is a keyword list of options.

  ### Options

  * See `display_name/2` for the supported options.

  ### Returns

  * A string representation of the language tag suitable for
    presentation.

  ### Raises

  * Raises an exception if the display name cannot be produced.

  ### Examples

      iex> Localize.Locale.LocaleDisplay.display_name!("en-US")
      "English (United States)"

      iex> Localize.Locale.LocaleDisplay.display_name!("en-US", language_display: :dialect)
      "American English"

  """
  @spec display_name!(Localize.LanguageTag.t() | String.t() | atom(), display_options()) ::
          String.t()
  def display_name!(language_tag, options \\ []) do
    case display_name(language_tag, options) do
      {:ok, name} -> name
      {:error, exception} -> raise exception
    end
  end

  # ── Data Loading ─────────────────────────────────────────────

  defp load_display_names(locale_id) do
    with {:ok, locale_display_names} <- Localize.Locale.get(locale_id, [:locale_display_names]),
         {:ok, languages} <- Localize.Locale.get(locale_id, [:languages]),
         {:ok, territories} <- Localize.Locale.get(locale_id, [:territories]),
         {:ok, bracket_replacements} <-
           Localize.Locale.get(locale_id, [:nested_bracket_replacement]) do
      display_names =
        locale_display_names
        |> Map.put(:language, languages)
        |> Map.put(:territory, territories)
        |> Map.put(:nested_bracket_replacement, bracket_replacements)

      {:ok, display_names}
    end
  end

  # ── Language Name Resolution ─────────────────────────────────

  defp language_name(language_tag, display_names, prefer, standard_or_dialect) do
    match_fun = &language_match_fun(&1, &2, :language, prefer, display_names)

    case first_match(language_tag, match_fun, standard_or_dialect) do
      {matched_tags, name} ->
        {:ok, matched_tags, name}

      nil ->
        {:error, Localize.LocaleDisplayError.exception(locale: language_tag)}
    end
  end

  defp language_match_fun(locale_name, matched_tags, field, prefer, display_names) do
    cond do
      display_name = get_in(display_names, [field, locale_name, prefer]) ->
        {matched_tags, display_name}

      display_name = get_in(display_names, [field, locale_name, :standard]) ->
        {matched_tags, display_name}

      true ->
        nil
    end
  end

  # ── First Match (locale name specificity cascade) ────────────

  # Tries locale name combinations from most specific to least:
  # lang-script-territory → lang-script → lang-territory → lang
  # Per TR35 the two-subtag tie is broken toward the subtag matching
  # earlier in the identifier, so lang-script precedes lang-territory.

  defp first_match(language_tag, match_fun, :dialect) do
    do_first_match(language_tag, match_fun)
  end

  defp first_match(language_tag, match_fun, :standard) do
    # Standard mode: temporarily remove territory and script so
    # they're not consumed in the language name and instead appear
    # as subtags (e.g., "English (United States)" not "American English")
    stripped_tag =
      Enum.reduce(@reinstate_subtags, language_tag, fn key, tag ->
        Map.put(tag, key, nil)
      end)

    case do_first_match(stripped_tag, match_fun) do
      {matched_tags, name} ->
        {matched_tags -- @reinstate_subtags, name}

      nil ->
        nil
    end
  end

  defp do_first_match(language_tag, match_fun) do
    %{language: language, script: script, territory: territory} = language_tag
    variants = Map.get(language_tag, :language_variants, [])

    # Try with variants first if present
    if variants != [] do
      try_matches_with_variants(language, script, territory, variants, match_fun) ||
        try_matches(language, script, territory, match_fun)
    else
      try_matches(language, script, territory, match_fun)
    end
  end

  defp try_matches(language, script, territory, fun) do
    locale_name_from(language, script, territory) |> fun.([:language, :script, :territory]) ||
      locale_name_from(language, script, nil) |> fun.([:language, :script]) ||
      locale_name_from(language, nil, territory) |> fun.([:language, :territory]) ||
      locale_name_from(language, nil, nil) |> fun.([:language])
  end

  defp try_matches_with_variants(language, script, territory, variants, fun) do
    variant_str = Enum.sort(variants) |> Enum.join("-")

    locale_name_from(language, script, territory, variant_str)
    |> fun.([:language, :script, :territory, :language_variants]) ||
      locale_name_from(language, script, nil, variant_str)
      |> fun.([:language, :script, :language_variants]) ||
      locale_name_from(language, nil, territory, variant_str)
      |> fun.([:language, :territory, :language_variants]) ||
      locale_name_from(language, nil, nil, variant_str)
      |> fun.([:language, :language_variants])
  end

  defp locale_name_from(language, script, territory, variant_str \\ nil) do
    [
      to_string(language),
      script && to_string(script),
      territory && to_string(territory),
      variant_str
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("-")
  end

  # ── Subtag Display Names ─────────────────────────────────────

  defp subtag_names(_locale, [], _prefer, _display_names), do: []

  defp subtag_names(locale, subtags, prefer, display_names) do
    subtags
    |> Enum.map(&get_subtag_display(locale, display_names, &1, prefer))
    |> Enum.reject(&empty?/1)
  end

  defp get_subtag_display(locale, display_names, subtag, prefer) do
    case Map.get(locale, subtag) do
      [_ | _] = values ->
        values
        |> Enum.map(&subtag_value_display(display_names, subtag, &1))
        |> Enum.sort()

      nil ->
        nil

      value ->
        get_in(display_names, [subtag, value]) || value
    end
    |> get_display_preference(prefer)
  end

  defp subtag_value_display(display_names, subtag, value) do
    display = get_in(display_names, [subtag, value]) || value
    if display == "FONIPA", do: "fonipa", else: display
  end

  # ── Extension Display Names ──────────────────────────────────

  defp extension_display_names(language_tag, locale_id, display_names, options) do
    results = []

    # U extension (locale) — CLDR 48.2: -u- items appear before -t- items
    locale_ext = Map.get(language_tag, :locale, %{})

    results =
      if locale_ext != %{} and not is_nil(locale_ext) do
        name =
          Localize.Locale.LocaleDisplay.U.display_name(
            locale_ext,
            locale_id,
            display_names,
            options
          )

        if empty?(name), do: results, else: results ++ [name]
      else
        results
      end

    # T extension (transform)
    transform = Map.get(language_tag, :transform, %{})

    results =
      if transform != %{} and not is_nil(transform) do
        name =
          Localize.Locale.LocaleDisplay.T.display_name(
            transform,
            locale_id,
            display_names,
            options
          )

        if empty?(name), do: results, else: results ++ [name]
      else
        results
      end

    # Other extensions
    extensions = Map.get(language_tag, :extensions, %{})

    results =
      if extensions != %{} do
        name =
          Localize.Locale.LocaleDisplay.Extension.display_name(
            extensions,
            locale_id,
            display_names
          )

        if empty?(name), do: results, else: results ++ [name]
      else
        results
      end

    results
  end

  # ── Format Assembly ──────────────────────────────────────────

  defp format_display_name(
         %{core: core, extension: extension},
         subtag_names,
         extension_names,
         display_names
       ) do
    format_display_name(core, [extension | subtag_names], extension_names, display_names)
  end

  defp format_display_name(%{alt: alt}, subtag_names, extension_names, display_names) do
    format_display_name(alt, subtag_names, extension_names, display_names)
  end

  defp format_display_name(language_name, [], [], display_names) do
    replace_nested_brackets(language_name, display_names)
  end

  defp format_display_name(language_name, subtag_names, extension_names, display_names) do
    language_name = replace_nested_brackets(language_name, display_names)
    locale_pattern = get_in(display_names, [:locale_display_pattern, :locale_pattern])

    subtags =
      [subtag_names, extension_names]
      |> Enum.reject(&empty?/1)
      |> join_subtags(display_names)

    [language_name, subtags]
    |> Localize.Substitution.substitute(locale_pattern)
    |> List.to_string()
  end

  # ── Helpers ──────────────────────────────────────────────────

  defp merge_extensions_and_private_use(%{private_use: []} = tag), do: tag

  defp merge_extensions_and_private_use(%{private_use: private_use} = tag)
       when is_list(private_use) and private_use != [] do
    extensions = Map.put_new(Map.get(tag, :extensions, %{}), "x", private_use)
    Map.put(tag, :extensions, extensions)
  end

  defp merge_extensions_and_private_use(tag), do: tag

  @doc false
  def get_display_preference(nil, _preference), do: nil
  def get_display_preference(value, _preference) when is_binary(value), do: value
  def get_display_preference(value, _preference) when is_atom(value), do: to_string(value)

  def get_display_preference(values, preference) when is_list(values) do
    Enum.map(values, &get_display_preference(&1, preference))
  end

  def get_display_preference(values, preference) when is_map(values) do
    Map.get(values, preference) || Map.get(values, :standard) ||
      Map.get(values, Map.keys(values) |> hd())
  end

  @doc false
  def replace_nested_brackets(value, display_names)

  def replace_nested_brackets(value, display_names) when is_binary(value) do
    replacements = Map.get(display_names, :nested_bracket_replacement, %{})

    if replacements == %{} do
      value
    else
      Enum.reduce(replacements, value, fn {from, to}, acc ->
        String.replace(acc, from, to)
      end)
    end
  end

  def replace_nested_brackets(value, _display_names), do: value

  @doc false
  def join_field_values([], _display_names), do: []

  def join_field_values(fields, display_names) do
    join_pattern = get_in(display_names, [:locale_display_pattern, :locale_separator])
    Enum.reduce(fields, &Localize.Substitution.substitute([&2, &1], join_pattern))
  end

  defp join_subtags([], _display_names), do: []
  defp join_subtags([field], _display_names), do: [field]

  defp join_subtags(fields, display_names) do
    join_pattern = get_in(display_names, [:locale_display_pattern, :locale_separator])
    Enum.reduce(fields, &Localize.Substitution.substitute([&2, &1], join_pattern))
  end

  defp validate_language_display(style) when style in [:standard, :dialect], do: :ok

  defp validate_language_display(invalid) do
    {:error,
     Localize.InvalidValueError.exception(
       value: invalid,
       expected: ":standard or :dialect"
     )}
  end

  defp resolve_locale_id(options) do
    # Route through the canonical CLDR locale resolver so user-supplied
    # binary or atom locales are validated against CLDR before any
    # atomisation. Falls back to `:en` if the locale is unresolvable so
    # that display formatting itself never raises on bad input.
    locale = Keyword.get(options, :locale, Localize.get_locale())

    case Localize.Locale.cldr_locale_id_from(locale) do
      {:ok, id} -> id
      {:error, _} -> :en
    end
  end

  defp empty?(nil), do: true
  defp empty?([]), do: true
  defp empty?(""), do: true
  defp empty?(%{} = map) when map == %{}, do: true
  defp empty?(_), do: false
end
