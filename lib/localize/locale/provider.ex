defmodule Localize.Locale.Provider do
  @moduledoc """
  Provides CLDR locale data from local data files.

  This module replaces `Cldr.Config` as the data source for
  locale-related information. All data is stored as Erlang
  external term format (`.etf`) files in `priv/cldr/` and
  loaded at compile time or on demand.

  """

  defp cldr_dir do
    :localize
    |> :code.priv_dir()
    |> to_string()
    |> Path.join("cldr")
  end

  @doc """
  Returns the likely subtags data as a map.

  Each key is a string like `"en"` or `"und-Latn"` and each
  value is a map with `:language`, `:script`, and `:territory`
  keys.

  """
  @spec likely_subtags() :: %{String.t() => map()}
  def likely_subtags do
    load_data("likely_subtags.etf")
  end

  @doc """
  Returns the alias data as a map with keys `:language`,
  `:script`, `:region`, `:variant`, `:subdivision`, and `:zone`.

  """
  @spec aliases() :: map()
  def aliases do
    load_data("aliases.etf")
  end

  @doc """
  Returns the language matching data as a map with keys
  `:language_match`, `:match_variables`, and `:paradigm_locales`.

  """
  @spec language_matching() :: map()
  def language_matching do
    load_data("language_matching.etf")
  end

  @doc """
  Returns the list of all known locale identifier atoms.

  """
  @spec all_locale_ids() :: [atom()]
  def all_locale_ids do
    load_data("all_locale_names.etf")
  end

  @doc """
  Returns validity data for the given type.

  ### Arguments

  * `type` is one of `:languages`, `:scripts`, `:territories`,
    `:variants`, `:u`, or `:t`.

  ### Returns

  * A map of validity data for the given type.

  """
  @spec validity(atom()) :: map()
  def validity(:u), do: load_data("validity_u.etf")
  def validity(:t), do: load_data("validity_t.etf")
  def validity(:languages), do: load_data("validity_languages.etf")
  def validity(:scripts), do: load_data("validity_scripts.etf")
  def validity(:territories), do: load_data("validity_territories.etf")
  def validity(:variants), do: load_data("validity_variants.etf")
  def validity(:subdivisions), do: load_data("validity_subdivisions.etf")
  def validity(:units), do: load_data("validity_units.etf")

  @doc """
  Returns the timezone data as a map.

  Each key is a BCP 47 timezone identifier string and each
  value is a map with `:preferred`, `:aliases`, and `:territory`
  keys.

  """
  @spec timezones() :: map()
  def timezones do
    load_data("timezones.etf")
  end

  @doc """
  Returns a mapping from Unicode script names to BCP 47
  script subtag atoms.

  """
  @spec unicode_script_to_subtag_mapping() :: map()
  def unicode_script_to_subtag_mapping do
    load_data("unicode_script_to_subtag_mapping.etf")
  end

  defp load_data(filename) do
    cldr_dir()
    |> Path.join(filename)
    |> File.read!()
    |> :erlang.binary_to_term()
  end
end
