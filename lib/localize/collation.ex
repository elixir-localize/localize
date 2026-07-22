defmodule Localize.Collation do
  @moduledoc """
  Implements the Unicode Collation Algorithm (UCA) as extended by CLDR.

  Collation is the general term for the process and function of
  determining the sorting order of strings of characters, for example for
  lists of strings presented to users, or in databases for sorting and selecting
  records.

  Collation varies by language, by application (some languages use special
  phonebook sorting), and other criteria (for example, phonetic vs. visual).

  CLDR provides collation data for many languages and styles. The data
  supports not only sorting but also language-sensitive searching and grouping
  under index headers. All CLDR collations are based on the [UCA] default order,
  with common modifications applied in the CLDR root collation, and further
  tailored for language and style as needed.

  ## Basic Usage

      # Compare two strings
      iex> Localize.Collation.compare("café", "cafe")
      :gt

      # Sort a list of strings
      iex> Localize.Collation.sort(["café", "cafe", "Cafe"])
      ["cafe", "Cafe", "café"]

      # Generate a sort key
      iex> key = Localize.Collation.sort_key("hello")
      iex> is_binary(key)
      true

      # With options
      iex> Localize.Collation.compare("a", "A", strength: :secondary)
      :eq

      # From BCP47 locale (ks-level2 = secondary strength, ignores case)
      iex> Localize.Collation.compare("a", "A", locale: "en-u-ks-level2")
      :eq

  ## Collation Options

  All BCP47 -u- extension collation keys are supported:

  * `strength` - `:primary`, `:secondary`, `:tertiary` (default), `:quaternary`, `:identical`.

  * `alternate` - `:non_ignorable` (default), `:shifted`.

  * `backwards` - `false` (default), `true` - reverse secondary weights (French).

  * `normalization` - `false` (default), `true` - NFD normalize input.

  * `case_level` - `false` (default), `true` - insert case-only level.

  * `case_first` - `false` (default), `:upper`, `:lower`.

  * `numeric` - `false` (default), `true` - numeric string comparison.

  * `reorder` - `[]` (default), list of script code atoms.

  * `max_variable` - `:punct` (default), `:space`, `:symbol`, `:currency`.

  * `ignore_accents` - `true` to ignore accent differences (sets strength to primary).

  * `ignore_case` - `true` to ignore case differences (sets strength to secondary).

  * `ignore_punctuation` - `true` to ignore punctuation and whitespace (sets alternate to shifted).

  * `casing` - `:sensitive`, `:insensitive` (convenience alias).

  * `backend` - `:nif` or `:elixir`. The default is `:elixir`.

  ## Return value convention

  Unlike the rest of Localize, the functions in this module return bare values rather than `{:ok, result}` tuples: `compare/3` returns `:lt`, `:eq` or `:gt` (the shape `Enum.sort/2` and friends expect for a comparator), `sort/2` returns the sorted list, and `sort_key/2` returns a binary. This deviation is deliberate — collation functions are designed to be passed directly to `Enum` and used in hot paths, where a wrapping tuple would defeat their purpose. Consistent with that design, unrecognised option values fall back to their defaults rather than producing an error.

  """

  alias Localize.Collation.{
    FastLatin,
    Han,
    ImplicitWeights,
    Nif,
    Normalizer,
    Options,
    Reorder,
    SortKey,
    Table,
    Variable
  }

  @doc """
  Compare two strings using the CLDR collation algorithm.

  ### Arguments

  * `string_a` - the first string to compare.

  * `string_b` - the second string to compare.

  * `options` - a keyword list of collation options.

  ### Options

  * `:strength` - comparison level: `:primary`, `:secondary`, `:tertiary` (default),
    `:quaternary`, or `:identical`.

  * `:alternate` - variable weight handling: `:non_ignorable` (default) or `:shifted`.

  * `:backwards` - reverse secondary weights for French sorting: `false` (default) or `true`.

  * `:normalization` - NFD normalize input: `false` (default) or `true`.

  * `:case_level` - insert case-only comparison level: `false` (default) or `true`.

  * `:case_first` - case ordering: `false` (default), `:upper`, or `:lower`.

  * `:numeric` - numeric string comparison: `false` (default) or `true`.

  * `:reorder` - list of script code atoms to reorder: `[]` (default).

  * `:max_variable` - variable weight boundary: `:punct` (default), `:space`,
    `:symbol`, or `:currency`.

  * `:ignore_accents` - `true` to ignore accent differences.

  * `:ignore_case` - `true` to ignore case differences.

  * `:ignore_punctuation` - `true` to ignore punctuation and whitespace.

  * `:casing` - `:sensitive` or `:insensitive`.

  * `:locale` - a BCP47 locale string or a `Localize.LanguageTag` struct.

  * `:backend` - `:nif` or `:elixir`. The default is `:elixir`.

  ### Returns

  * `:lt` - if `string_a` sorts before `string_b`.

  * `:eq` - if `string_a` and `string_b` are equal at the given strength.

  * `:gt` - if `string_a` sorts after `string_b`.

  ### Examples

      iex> Localize.Collation.compare("cafe", "café")
      :lt

      iex> Localize.Collation.compare("a", "A", strength: :secondary)
      :eq

      iex> Localize.Collation.compare("a", "A", casing: :insensitive)
      :eq

  """
  @spec compare(String.t(), String.t(), keyword() | Options.t()) :: :lt | :eq | :gt
  def compare(string_a, string_b, options \\ []) do
    options = resolve_options(options)

    if use_nif?(options) do
      Nif.nif_compare(string_a, string_b, options)
    else
      key_a = sort_key(string_a, options)
      key_b = sort_key(string_b, options)

      cond do
        key_a < key_b -> :lt
        key_a > key_b -> :gt
        true -> :eq
      end
    end
  end

  @doc """
  Generate a binary sort key for the given input.

  Sort keys can be compared directly with `<`, `>`, `==` for ordering.
  This is efficient when the same strings need to be compared multiple times.

  ### Arguments

  * `input` - a UTF-8 string or a list of integer codepoints.

  * `options` - a keyword list of collation options, or a `t:Localize.Collation.Options.t/0` struct.

  ### Options

  * `:locale` - a BCP47 locale string, atom, or a `Localize.LanguageTag` struct.
    The default is `Localize.get_locale/0`. Collation settings from the locale's
    `-u-` extension (e.g. `-u-ks-level2`) and its CLDR tailoring are combined
    with the explicitly given options.

  * `:strength` - comparison level: `:primary`, `:secondary`, `:tertiary` (default),
    `:quaternary`, or `:identical`.

  * `:alternate` - variable weight handling: `:non_ignorable` (default) or `:shifted`.

  * `:backwards` - reverse secondary weights for French sorting: `false` (default) or `true`.

  * `:normalization` - NFD normalize input: `false` (default) or `true`.

  * `:case_level` - insert case-only comparison level: `false` (default) or `true`.

  * `:case_first` - case ordering: `false` (default), `:upper`, or `:lower`.

  * `:numeric` - numeric string comparison: `false` (default) or `true`.

  * `:reorder` - a script code atom or list of script code atoms to reorder: `[]` (default).

  * `:max_variable` - variable weight boundary: `:punct` (default), `:space`,
    `:symbol`, or `:currency`.

  * `:type` - collation type: `:standard` (default), `:search`, `:phonebook`,
    `:pinyin`, `:stroke`, `:unihan`, `:zhuyin`, `:searchjl`, `:eor`, or `:traditional`.

  * `:ignore_accents` - `true` to ignore accent differences.

  * `:ignore_case` - `true` to ignore case differences.

  * `:ignore_punctuation` - `true` to ignore punctuation and whitespace.

  * `:casing` - `:sensitive` or `:insensitive`.

  * `:backend` - `:nif` or `:elixir`. The default is `:elixir`.

  ### Returns

  A binary sort key that can be compared with standard binary comparison operators.

  ### Examples

      iex> key_a = Localize.Collation.sort_key("cafe")
      iex> key_b = Localize.Collation.sort_key("café")
      iex> key_a < key_b
      true

      iex> Localize.Collation.sort_key("hello") == Localize.Collation.sort_key("hello")
      true

  """
  @spec sort_key(String.t() | [non_neg_integer()], keyword() | Options.t()) :: binary()
  def sort_key(input, options \\ [])

  def sort_key(input, options) when is_list(options) do
    sort_key(input, resolve_options(options))
  end

  def sort_key(string, %Options{} = options) when is_binary(string) do
    ensure_loaded()
    codepoints = Normalizer.normalize_to_codepoints(string, options.normalization)
    build_sort_key(codepoints, options, string)
  end

  def sort_key(codepoints, %Options{} = options) when is_list(codepoints) do
    ensure_loaded()

    codepoints =
      if options.normalization do
        codepoints
        |> List.to_string()
        |> Normalizer.normalize_to_codepoints(true)
      else
        codepoints
      end

    build_sort_key(codepoints, options, nil)
  end

  defp build_sort_key(codepoints, options, original_string) do
    elements = produce_collation_elements(codepoints, options)

    variable_range = Variable.primary_range(options.max_variable)
    processed = Variable.process(elements, options.alternate, variable_range)

    processed =
      case Reorder.build_mapping(options.reorder) do
        nil ->
          processed

        mapping_fn ->
          Enum.map(processed, fn {{p, s, t, v}, q} ->
            {{mapping_fn.(p), s, t, v}, q}
          end)
      end

    SortKey.build(processed, options, original_string)
  end

  @doc """
  Sort a list of strings using the CLDR collation algorithm.

  ### Arguments

  * `strings` - a list of UTF-8 strings to sort.

  * `options` - a keyword list of collation options.

  ### Options

  * `:locale` - a BCP47 locale string, atom, or a `Localize.LanguageTag` struct.
    The default is `Localize.get_locale/0`. Collation settings from the locale's
    `-u-` extension (e.g. `-u-ks-level2`) and its CLDR tailoring are combined
    with the explicitly given options.

  * `:strength` - comparison level: `:primary`, `:secondary`, `:tertiary` (default),
    `:quaternary`, or `:identical`.

  * `:alternate` - variable weight handling: `:non_ignorable` (default) or `:shifted`.

  * `:backwards` - reverse secondary weights for French sorting: `false` (default) or `true`.

  * `:normalization` - NFD normalize input: `false` (default) or `true`.

  * `:case_level` - insert case-only comparison level: `false` (default) or `true`.

  * `:case_first` - case ordering: `false` (default), `:upper`, or `:lower`.

  * `:numeric` - numeric string comparison: `false` (default) or `true`.

  * `:reorder` - a script code atom or list of script code atoms to reorder: `[]` (default).

  * `:max_variable` - variable weight boundary: `:punct` (default), `:space`,
    `:symbol`, or `:currency`.

  * `:type` - collation type: `:standard` (default), `:search`, `:phonebook`,
    `:pinyin`, `:stroke`, `:unihan`, `:zhuyin`, `:searchjl`, `:eor`, or `:traditional`.

  * `:ignore_accents` - `true` to ignore accent differences.

  * `:ignore_case` - `true` to ignore case differences.

  * `:ignore_punctuation` - `true` to ignore punctuation and whitespace.

  * `:casing` - `:sensitive` or `:insensitive`.

  * `:backend` - `:nif` or `:elixir`. The default is `:elixir`.

  ### Returns

  A new list of strings sorted according to the CLDR collation rules.

  ### Examples

      iex> Localize.Collation.sort(["café", "cafe", "Cafe"])
      ["cafe", "Cafe", "café"]

      iex> Localize.Collation.sort(["б", "а", "в"])
      ["а", "б", "в"]

  """
  @spec sort([String.t()], keyword() | Options.t()) :: [String.t()]
  def sort(strings, options \\ []) do
    options = resolve_options(options)

    if use_nif?(options) do
      Enum.sort(strings, fn a, b ->
        Nif.nif_compare(a, b, options) in [:lt, :eq]
      end)
    else
      strings
      |> Enum.map(fn s -> {sort_key(s, options), s} end)
      |> Enum.sort_by(fn {key, _s} -> key end)
      |> Enum.map(fn {_key, s} -> s end)
    end
  end

  @doc """
  Returns the CLDR collation identifiers.

  These are the BCP 47 `-u-co-` values from the CLDR inventory, the same identifiers accepted by the `-u-co-` locale keyword. The full inventory is returned, including `"standard"` and `"search"` — callers implementing ECMA-402's `Intl.supportedValuesOf("collation")` should exclude those two per that specification. Note that not every identifier has tailoring data in every locale; identifiers without a tailoring for a locale fall back to the root collation.

  ### Returns

  * A sorted list of collation identifier strings.

  ### Examples

      iex> collations = Localize.Collation.known_collations()
      iex> "phonebk" in collations and "pinyin" in collations
      true

      iex> Localize.Collation.known_collations() |> Enum.take(4)
      ["big5han", "compat", "dict", "direct"]

  """
  @spec known_collations() :: [String.t(), ...]
  def known_collations do
    Localize.SupplementalData.validity(:u)
    |> Map.fetch!("co")
    |> Map.keys()
    |> Enum.sort()
  end

  @doc """
  Ensure the collation tables are loaded into persistent term storage.

  ### Returns

  * `:ok` - tables are loaded and ready.

  ### Examples

      iex> Localize.Collation.ensure_loaded()
      :ok

  """
  @spec ensure_loaded() :: :ok
  def ensure_loaded do
    Table.ensure_loaded()
  end

  # Internal: produce collation elements from codepoints

  defp produce_collation_elements(codepoints, options) do
    if options.numeric do
      produce_with_numeric(codepoints, options)
    else
      produce_standard(
        codepoints,
        options.tailoring,
        options.suppress_contractions,
        options.han_ordering
      )
    end
  end

  defp produce_standard(codepoints, overlay, suppress, han_ordering) do
    do_produce(codepoints, [], overlay, suppress, han_ordering)
  end

  defp do_produce([], acc, _overlay, _suppress, _han_ordering),
    do: Enum.reverse(acc) |> List.flatten()

  # FastLatin shortcut: only when there is no tailoring overlay,
  # since overlays may remap characters in the Latin range.
  defp do_produce([cp | rest], acc, nil, suppress, han_ordering) when cp < 0x0180 do
    case FastLatin.lookup(cp) do
      nil ->
        do_produce_full([cp | rest], acc, nil, suppress, han_ordering)

      elements ->
        do_produce(rest, [elements | acc], nil, suppress, han_ordering)
    end
  end

  defp do_produce(codepoints, acc, overlay, suppress, han_ordering) do
    do_produce_full(codepoints, acc, overlay, suppress, han_ordering)
  end

  defp do_produce_full([cp | rest] = codepoints, acc, overlay, suppress, han_ordering) do
    # When a codepoint is in the suppress list, skip contraction
    # lookup and look up only the single codepoint.
    if suppress != [] and cp in suppress do
      case Table.lookup(cp) do
        {:ok, elements} ->
          do_produce(rest, [elements | acc], overlay, suppress, han_ordering)

        :unmapped ->
          elements = resolve_unmapped(cp, han_ordering)
          do_produce(rest, [elements | acc], overlay, suppress, han_ordering)
      end
    else
      case Table.longest_match_with_overlay(codepoints, overlay) do
        {matched, elements, remaining} when is_list(elements) ->
          {final_elements, final_remaining} =
            try_discontiguous_match(matched, elements, remaining)

          do_produce(final_remaining, [final_elements | acc], overlay, suppress, han_ordering)

        {:unmapped, cp, remaining} ->
          elements = resolve_unmapped(cp, han_ordering)

          {final_elements, final_remaining} =
            try_discontiguous_match([cp], elements, remaining)

          do_produce(final_remaining, [final_elements | acc], overlay, suppress, han_ordering)

        :done ->
          Enum.reverse(acc) |> List.flatten()
      end
    end
  end

  defp try_discontiguous_match(matched_cps, elements, remaining) do
    case remaining do
      [] ->
        {elements, remaining}

      _ ->
        {combiners, rest} = collect_combining(remaining, [])

        if combiners == [] do
          {elements, remaining}
        else
          {new_elements, _consumed, unconsumed} =
            extend_with_combiners(matched_cps, elements, combiners)

          new_remaining = unconsumed ++ rest
          {new_elements, new_remaining}
        end
    end
  end

  defp collect_combining([cp | rest], acc) do
    ccc = combining_class(cp)

    if ccc > 0 do
      collect_combining(rest, [{cp, ccc} | acc])
    else
      {Enum.reverse(acc), [cp | rest]}
    end
  end

  defp collect_combining([], acc), do: {Enum.reverse(acc), []}

  defp extend_with_combiners(base_cps, base_elements, combiners) do
    {final_elements, consumed_set, _last_ccc, _current_base} =
      Enum.reduce(combiners, {base_elements, MapSet.new(), 0, base_cps}, fn
        {cp, ccc}, {elems, consumed, last_ccc, current_base} ->
          if ccc > 0 and (last_ccc == 0 or ccc > last_ccc) do
            extend_with_combiner(current_base ++ [cp], cp, ccc, elems, consumed, current_base)
          else
            {elems, consumed, last_ccc, current_base}
          end
      end)

    unconsumed =
      Enum.reject(combiners, fn {cp, _ccc} -> MapSet.member?(consumed_set, cp) end)
      |> Enum.map(fn {cp, _ccc} -> cp end)

    {final_elements, consumed_set, unconsumed}
  end

  defp extend_with_combiner(candidate, cp, ccc, elements, consumed, current_base) do
    case Table.lookup(candidate) do
      {:ok, new_elements} ->
        {new_elements, MapSet.put(consumed, cp), ccc, candidate}

      :unmapped ->
        {elements, consumed, ccc, current_base}
    end
  end

  defp combining_class(cp) do
    Localize.Collation.Unicode.combining_class(cp)
  end

  defp produce_with_numeric(codepoints, options) do
    pairs = collect_ce_pairs(codepoints, [], options.han_ordering)
    Localize.Collation.Numeric.process_elements(pairs)
  end

  defp collect_ce_pairs([], acc, _han_ordering), do: Enum.reverse(acc)

  defp collect_ce_pairs(codepoints, acc, han_ordering) do
    case Table.longest_match(codepoints) do
      {matched, elements, remaining} when is_list(elements) ->
        collect_ce_pairs(remaining, [{matched, elements} | acc], han_ordering)

      {:unmapped, cp, remaining} ->
        elements = resolve_unmapped(cp, han_ordering)
        collect_ce_pairs(remaining, [{[cp], elements} | acc], han_ordering)

      :done ->
        Enum.reverse(acc)
    end
  end

  defp resolve_unmapped(cp, han_ordering) do
    # For CJK Unified Ideographs, use radical-stroke ordering (UAX #38)
    # when the locale has requested it via the `:han_ordering` option
    # (set for the `-u-co-unihan` collation type). All other locales —
    # including root — use UCA implicit weights, matching the CLDR
    # root collation and the conformance test data.
    if han_ordering == :radical_stroke and ImplicitWeights.unified_ideograph?(cp) do
      case Han.collation_elements(cp) do
        nil -> ImplicitWeights.compute(cp)
        elements -> elements
      end
    else
      resolve_implicit_weights(ImplicitWeights.compute(cp))
    end
  end

  defp resolve_implicit_weights({:hangul_decompose, jamo}) do
    Enum.flat_map(jamo, &jamo_collation_elements/1)
  end

  defp resolve_implicit_weights(elements) when is_list(elements) do
    elements
  end

  defp jamo_collation_elements(jamo) do
    case Table.lookup(jamo) do
      {:ok, elements} -> elements
      :unmapped -> ImplicitWeights.compute(jamo)
    end
  end

  defp resolve_options(options) when is_list(options) do
    case Keyword.get(options, :locale) do
      nil ->
        # Default to the current process locale so that collation
        # respects `Localize.put_locale/1` the same way every other
        # formatting module does.
        options_from_language_tag(Localize.get_locale(), options)

      locale when is_binary(locale) ->
        rest = Keyword.delete(options, :locale)
        options_from_locale_string(locale, rest)

      %Localize.LanguageTag{} = tag ->
        rest = Keyword.delete(options, :locale)
        options_from_language_tag(tag, rest)

      locale when is_atom(locale) ->
        rest = Keyword.delete(options, :locale)
        options_from_locale_string(Atom.to_string(locale), rest)

      _locale ->
        Options.new(Keyword.delete(options, :locale))
    end
  end

  defp resolve_options(%Options{} = options), do: options

  defp options_from_locale_string(locale, extra_options) do
    # Validate the locale to get a fully canonicalized LanguageTag
    # with the U extension parsed into a LanguageTag.U struct.
    case Localize.validate_locale(locale) do
      {:ok, tag} ->
        options_from_language_tag(tag, extra_options)

      _ ->
        # Fallback to built-in BCP47 parser
        Options.from_locale(locale) |> struct(extra_options)
    end
  end

  defp options_from_language_tag(%Localize.LanguageTag{} = tag, extra_options) do
    alias Localize.Collation.Tailoring
    alias Localize.Collation.Tailoring.LocaleDefaults

    language = tag_language(tag)
    locale_defaults = LocaleDefaults.options_for(language)

    # Extract U extension options from the tag
    u = tag.locale
    u_options = extract_u_options(u)

    # Determine collation type
    type =
      Keyword.get(u_options, :type) ||
        Keyword.get(extra_options, :type) ||
        LocaleDefaults.default_type(language)

    # Look up the tailoring from the most specific identifier —
    # CLDR keys some tailorings by language-territory (fr-CA carries
    # `[backwards 2]` while plain fr has no tailoring at all); the
    # parent chain inside get_tailoring falls back to the bare
    # language when there is no territory-specific entry.
    {tailoring_overlay, tailoring_option_overrides} =
      case Tailoring.get_tailoring(tag_tailoring_locale(tag), type) do
        {overlay, overrides} -> {overlay, overrides}
        nil -> {nil, []}
      end

    # When a tailoring overlay is present, normalization must be
    # enabled so input is decomposed to NFD — the form used for
    # overlay keys.
    normalization =
      if tailoring_overlay != nil, do: [normalization: true], else: []

    # Resolve shorthand options (`casing:`, `ignore_accents:`,
    # `ignore_case:`, `ignore_punctuation:`) into their canonical
    # struct fields (`:strength`, `:alternate`, etc.) by running
    # them through `Options.new/1`. Then extract only the fields
    # that differ from the defaults so we don't overwrite locale,
    # U-extension, or tailoring-derived values.
    defaults = Options.new()
    resolved_extra = Options.new(extra_options)

    extra_overrides =
      resolved_extra
      |> Map.from_struct()
      |> Enum.reject(fn {key, value} -> Map.get(defaults, key) == value end)

    Options.new()
    |> struct(tailoring_option_overrides)
    |> struct(locale_defaults)
    |> struct(normalization)
    |> struct(u_options)
    |> struct(extra_overrides)
    |> Map.put(:type, type)
    |> Map.put(:tailoring, tailoring_overlay)
    |> Map.put(:han_ordering, han_ordering_for(type))
  end

  # Radical-stroke ordering for Han characters applies only when the
  # collation type specifically requests it. CLDR's root collation and
  # all other tailored locales use UCA implicit weights (codepoint
  # order) for Han, matching the reference behaviour.
  defp han_ordering_for(:unihan), do: :radical_stroke
  defp han_ordering_for(_type), do: :implicit

  defp tag_language(%Localize.LanguageTag{} = tag) do
    cond do
      is_atom(tag.language) and not is_nil(tag.language) ->
        Atom.to_string(tag.language)

      is_binary(tag.language) ->
        tag.language

      true ->
        "und"
    end
  end

  defp tag_tailoring_locale(%Localize.LanguageTag{} = tag) do
    language = tag_language(tag)

    case tag.territory do
      nil -> language
      territory -> language <> "-" <> to_string(territory)
    end
  end

  defp extract_u_options(nil), do: []

  defp extract_u_options(%Localize.LanguageTag.U{} = u) do
    []
    |> maybe_put(:type, u.co)
    |> maybe_put(:strength, u.ks)
    |> maybe_put(:alternate, u.ka)
    |> maybe_put(:backwards, u_bool_value(u.kb))
    |> maybe_put(:normalization, u_bool_value(u.kk))
    |> maybe_put(:case_level, u_bool_value(u.kc))
    |> maybe_put(:case_first, u.kf)
    |> maybe_put(:numeric, u_bool_value(u.kn))
    |> maybe_put(:reorder, u.kr)
    |> maybe_put(:max_variable, u.kv)
  end

  defp extract_u_options(_), do: []

  defp u_bool_value(:yes), do: true
  defp u_bool_value(:no), do: false
  defp u_bool_value(_), do: nil

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp use_nif?(%Options{backend: :nif} = options) do
    Nif.available?() and Options.nif_compatible?(options)
  end

  defp use_nif?(_options), do: false
end
