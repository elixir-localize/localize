defmodule Localize.Locale.Inheritance do
  @moduledoc false

  # TR35 locale inheritance over a locale's subtags: one step up, and the
  # resource-bundle lookup that finds the CLDR locale whose data a locale
  # gets. `Localize.Locale.parent/2` and `Localize.LanguageTag.new/1` both
  # go through here, so a parent and a resolution never disagree.
  #
  # Everything here reads a tag's `language`, `script`, `territory` and
  # `language_variants` only, and returns tags with no `cldr_locale_id`
  # and no extensions; naming the CLDR locale and carrying extensions is
  # the caller's. Every lookup is keyed by strings or by atoms that
  # already exist, so no atom is made.

  alias Localize.LanguageTag
  alias Localize.SupplementalData

  @doc false
  # TR35's parent of a locale's subtags: the component's `parentLocales`,
  # then for the main component the non-likely-script rule, then
  # truncation. The root's parent is the root; callers stop there.
  @spec parent(LanguageTag.t(), Localize.Locale.inheritance_component()) :: LanguageTag.t()
  def parent(%LanguageTag{} = tag, component) do
    subtags = subtags(tag)

    case listed_parent(subtags, component) do
      {:ok, parent_id} -> named_parent(parent_id)
      :error -> unlisted_parent(subtags, component)
    end
  end

  @doc false
  # The CLDR locale whose data a locale gets, by TR35's resource-bundle
  # lookup, or `:und` for the root. `index` maps each CLDR locale's name
  # to its atom.
  #
  # A locale that is a CLDR locale as asked for is that locale: `zh-Hans`
  # and `sr-Cyrl` have data of their own. Otherwise the lookup starts from
  # the locale without a script likely subtags imply (`de-Latn-LI` starts
  # at `de-LI`, `ar-Arab-EG` at `ar-EG`), as TR35's Lookup section says,
  # and takes the first CLDR locale on the way
  # up. A `lang-Region` is read once as its likely `lang-Script-Region`
  # ("lang_region aliases to lang_script_region"), unless `parentLocales`
  # names its parent: `zh-TW` is `zh-Hant-TW`, whose parent is `zh-Hant`.
  # A locale with a variant that is no CLDR locale is tried once more
  # without the subtags likely subtags imply, since a variant names data
  # of its own: `be-Cyrl-BY-tarask` is `be-tarask`.
  @spec bundle_locale_id(LanguageTag.t(), %{String.t() => atom()}) :: atom()
  def bundle_locale_id(%LanguageTag{language: :und, script: nil, territory: nil}, _index) do
    :und
  end

  # TR35's Lookup canonicalizes the locale by likely subtags first, and
  # they give `und` with a script or territory a language: `und-TW` is
  # Chinese. ICU's resource lookup reads it as the root instead; Localize
  # keeps the language likely subtags give.
  def bundle_locale_id(%LanguageTag{language: :und} = tag, index) do
    requested = subtags(tag)

    case LanguageTag.add_likely_subtags(requested) do
      {:ok, %LanguageTag{language: :und}} ->
        :und

      {:ok, %LanguageTag{language: language}} ->
        bundle_locale_id(%{requested | language: language}, index)

      {:error, _exception} ->
        :und
    end
  end

  def bundle_locale_id(%LanguageTag{} = tag, index) do
    requested = subtags(tag)

    case Map.fetch(index, name(requested)) do
      {:ok, locale_id} -> locale_id
      :error -> lookup(without_implied_script(requested), index)
    end
  end

  defp lookup(%LanguageTag{} = start, index) do
    case start_locale_id(start, index) do
      nil -> walk(start, index, false)
      locale_id -> locale_id
    end
  end

  @doc false
  # The script likely subtags give a language, in a territory where one is
  # given (`sr` in `RO` is `Latn`), or `nil` where they give none.
  @spec likely_script(atom(), atom() | nil) :: atom() | nil
  def likely_script(language, territory) do
    likely_subtags = SupplementalData.likely_subtags()

    language
    |> Atom.to_string()
    |> likely_keys(territory)
    |> Enum.find_value(&likely_script_for(likely_subtags, &1))
  end

  defp start_locale_id(%LanguageTag{} = start, index) do
    case Map.fetch(index, name(start)) do
      {:ok, locale_id} -> locale_id
      :error -> variant_locale_id(start, index)
    end
  end

  defp variant_locale_id(%LanguageTag{language_variants: [_ | _]} = start, index) do
    case LanguageTag.remove_likely_subtags(start, favor: :region) do
      {:ok, %LanguageTag{canonical_locale_id: minimized}} -> Map.get(index, minimized)
      {:error, _exception} -> nil
    end
  end

  defp variant_locale_id(%LanguageTag{}, _index) do
    nil
  end

  defp walk(%LanguageTag{language: :und, script: nil, territory: nil}, _index, _aliased) do
    :und
  end

  defp walk(%LanguageTag{} = tag, index, aliased) do
    case Map.fetch(index, name(tag)) do
      {:ok, locale_id} -> locale_id
      :error -> walk_up(tag, index, aliased)
    end
  end

  defp walk_up(%LanguageTag{} = tag, index, aliased) do
    if not aliased and aliases_to_script?(tag) do
      script = likely_script(tag.language, tag.territory)
      walk(%{tag | script: script}, index, true)
    else
      walk(parent(tag, :main), index, aliased)
    end
  end

  # A `lang-Region` with no parent of its own in `parentLocales`, whose
  # likely script is known.
  defp aliases_to_script?(%LanguageTag{script: nil, territory: territory} = tag)
       when not is_nil(territory) do
    listed_parent(tag, :main) == :error and
      not is_nil(likely_script(tag.language, territory))
  end

  defp aliases_to_script?(%LanguageTag{}) do
    false
  end

  defp without_implied_script(%LanguageTag{} = tag) do
    if implied_script?(tag) or implied_language_script?(tag) do
      %{tag | script: nil}
    else
      tag
    end
  end

  # A script with no territory, which likely subtags give the language
  # alone: `zh-Hans` starts at `zh`.
  defp implied_language_script?(%LanguageTag{script: script, territory: nil} = tag)
       when not is_nil(script) do
    script == likely_script(tag.language, nil)
  end

  defp implied_language_script?(%LanguageTag{}) do
    false
  end

  # The locale's subtags, without its extensions or ids.
  defp subtags(%LanguageTag{} = tag) do
    %{
      tag
      | locale: %{},
        transform: %{},
        extensions: %{},
        private_use: [],
        canonical_locale_id: nil,
        cldr_locale_id: nil
    }
  end

  defp name(%LanguageTag{} = tag) do
    Localize.Locale.locale_id_from(
      tag.language,
      tag.script,
      tag.territory,
      tag.language_variants
    )
  end

  # The parent `parentLocales` names for the locale, under its own name or
  # under its name without a script likely subtags imply, since TR35
  # treats the two as one locale: `en-Latn-RO` is `en-RO`, whose parent is
  # `en-150`.
  defp listed_parent(%LanguageTag{} = tag, component) do
    parent_locales = SupplementalData.parent_locales(component)

    tag
    |> identical_names()
    |> Enum.find_value(:error, &fetch_listed(parent_locales, &1))
  end

  defp identical_names(%LanguageTag{} = tag) do
    if implied_script?(tag) do
      [name(tag), name(%{tag | script: nil})]
    else
      [name(tag)]
    end
  end

  defp implied_script?(%LanguageTag{script: script, territory: territory} = tag)
       when not is_nil(script) and not is_nil(territory) do
    script == likely_script(tag.language, territory)
  end

  defp implied_script?(%LanguageTag{}) do
    false
  end

  defp fetch_listed(parent_locales, name) do
    case Map.fetch(parent_locales, name) do
      {:ok, parent_id} -> {:ok, parent_id}
      :error -> nil
    end
  end

  # A parent `parentLocales` names is CLDR's own data, always a valid
  # locale name.
  defp named_parent(parent_id) do
    {:ok, parsed} = LanguageTag.parse(parent_id)
    {:ok, canonical} = LanguageTag.canonicalize(parsed)
    subtags(canonical)
  end

  # TR35 applies the non-likely-script rule to the main component only:
  # collation and plural data do not mix scripts in text.
  defp unlisted_parent(%LanguageTag{} = tag, :main) do
    if nonlikely_script?(tag) do
      root()
    else
      truncated(tag)
    end
  end

  defp unlisted_parent(%LanguageTag{} = tag, _component) do
    truncated(tag)
  end

  # TR35's `localeRules="nonlikelyScript"`: a language and script, with no
  # territory or variant, whose script is not the one likely subtags give
  # the language. CLDR lists some of these locales for migration; the rule
  # covers every one, `ru-Latn` included.
  defp nonlikely_script?(
         %LanguageTag{script: script, territory: nil, language_variants: []} = tag
       )
       when not is_nil(script) do
    script != likely_script(tag.language, nil)
  end

  defp nonlikely_script?(%LanguageTag{}) do
    false
  end

  defp likely_keys(language, nil) do
    [{language, nil, nil}]
  end

  defp likely_keys(language, territory) do
    [{language, nil, Atom.to_string(territory)}, {language, nil, nil}]
  end

  defp likely_script_for(likely_subtags, key) do
    case Map.fetch(likely_subtags, key) do
      {:ok, %{script: script}} -> script
      :error -> nil
    end
  end

  # Truncation removes the last subtag: a variant, then the territory, then
  # the script; a language alone has the root as its parent.
  defp truncated(%LanguageTag{language_variants: [_ | _] = variants} = tag) do
    %{tag | language_variants: List.delete_at(variants, -1)}
  end

  defp truncated(%LanguageTag{territory: territory} = tag) when not is_nil(territory) do
    %{tag | territory: nil}
  end

  defp truncated(%LanguageTag{script: script} = tag) when not is_nil(script) do
    %{tag | script: nil}
  end

  defp truncated(%LanguageTag{}) do
    root()
  end

  defp root do
    %LanguageTag{
      language: :und,
      script: nil,
      territory: nil,
      language_variants: [],
      requested_locale_id: "und"
    }
  end
end
