defmodule Localize.LanguageTag.Parser do
  # Parses a CLDR language tag (also referred to as locale string).
  #
  # The applicable specification is from [CLDR](http://unicode.org/reports/tr35/#Unicode_Language_and_Locale_Identifiers)
  # which is similar based upon [RFC5646](https://tools.ietf.org/html/rfc5646) with some variations.
  #
  # This module performs grammar-level parsing only. It returns a bare
  # map with `language`, `script`, and `territory` as **strings** (no
  # atomization). Validity checking and atomization happen in
  # `Localize.LanguageTag.parse/1`, which gates atomization behind the
  # bounded validity sets so untrusted input cannot exhaust the atom
  # table.
  #
  @moduledoc false
  alias Localize.Locale

  @doc """
  Parse a locale identifier into a bare map of subtag fields.

  * `locale_id` is a string representation of a language tag
    as defined by [RFC5646](https://tools.ietf.org/html/rfc5646).

  Returns

  * `{:ok, map}` where `map` carries the parsed subtags. The
    `:language`, `:script`, and `:territory` values are
    normalised strings (not atoms); the caller is responsible for
    validating and atomising them.

  * `{:error, exception}` if the grammar parse fails.

  """
  @dialyzer {:nowarn_function, parse: 1}
  def parse(locale) do
    case Localize.Rfc5646.Parser.parse(normalize_locale_id(locale)) do
      {:ok, fields} ->
        map =
          fields
          |> Keyword.put(:requested_locale_id, locale)
          |> Enum.map(&normalize_field/1)
          |> Map.new()
          |> default_optional_fields()

        {:ok, map}

      {:error, %Localize.ParseError{}} = error ->
        error
    end
  end

  @doc """
  Parse a locale identifier into a bare map, raising on error.

  See `parse/1` for the return shape.

  """
  def parse!(locale) do
    case parse(locale) do
      {:ok, map} -> map
      {:error, exception} -> raise exception
    end
  end

  def normalize_field({:language = field, language}) do
    {field, Localize.Validity.Language.normalize(language)}
  end

  def normalize_field({:script = field, script}) do
    {field, Localize.Validity.Script.normalize(script)}
  end

  def normalize_field({:territory = field, territory}) do
    {field, Localize.Validity.Territory.normalize(territory)}
  end

  def normalize_field({:language_variants = field, variants}) do
    {field, Localize.Validity.Variant.normalize(variants)}
  end

  # Everything is downcased before parsing
  # and that's the canonical form so no need to
  # do it again, just return the value

  def normalize_field(other) do
    other
  end

  defp normalize_locale_id(locale_id) do
    locale_id
    |> String.downcase()
    |> Locale.locale_id_from_posix()
  end

  # The grammar emits subtags only when present in the input. Downstream
  # code (alias resolution, struct lifting) is simpler if the map always
  # carries the optional subtag keys with predictable empty defaults.
  defp default_optional_fields(map) do
    Map.merge(
      %{
        language: nil,
        script: nil,
        territory: nil,
        language_variants: [],
        language_subtags: [],
        locale: %{},
        transform: %{},
        extensions: %{},
        private_use: []
      },
      map
    )
  end
end
