defmodule Localize.Inflection.Data do
  @moduledoc false

  # Loads per-locale data artifacts on demand.
  #
  # The entire artifact for a locale — lexicon, grammeme registry,
  # inflection patterns, features, contractions — is stored under a
  # single `:persistent_term` key, `{__MODULE__, locale}`. Reads hit
  # the shared literal directly with no copy-out. This mirrors how
  # `Localize.Locale.Provider` holds each locale's CLDR data, so
  # inflection data rides the same write-once/read-many pattern.
  #
  # The lexicon is held as a packed `Localize.Inflection.Lexicon`
  # rather than a map: a map of a million surface forms costs roughly
  # seven times its own data in per-entry BEAM structure, which the
  # packed form removes (~10x smaller, measured). Artifacts ship
  # packed, so loading is a plain read — an artifact without a packed
  # lexicon predates the format and is reported as incompatible.
  #
  # A GenServer serializes loading so concurrent first requests for
  # the same locale load the artifact only once — one `put` per
  # locale over its lifetime, never a `put` over an existing key
  # (which would trigger a global GC).

  use GenServer

  alias Localize.Inflection.Lexicon

  @doc """
  Starts the data loader.

  """
  def start_link(options \\ []) do
    GenServer.start_link(__MODULE__, options, name: __MODULE__)
  end

  @doc """
  Ensures the artifact for `locale` is loaded, returning `:ok` or
  `{:error, reason}`.

  """
  def ensure_loaded(locale) when is_atom(locale) do
    if loaded?(locale) do
      :ok
    else
      GenServer.call(__MODULE__, {:load, locale}, :infinity)
    end
  end

  @doc """
  Returns true if the artifact for `locale` is loaded.

  """
  def loaded?(locale) when is_atom(locale) do
    :persistent_term.get({__MODULE__, locale}, nil) != nil
  end

  @doc """
  Returns the loaded artifact for `locale` (lexicon plus metadata),
  raising if the locale is not loaded and cannot be loaded.

  """
  def metadata!(locale) when is_atom(locale) do
    case :persistent_term.get({__MODULE__, locale}, nil) do
      nil ->
        case ensure_loaded(locale) do
          :ok ->
            :persistent_term.get({__MODULE__, locale})

          {:error, reason} ->
            raise ArgumentError, "cannot load locale #{locale}: #{inspect(reason)}"
        end

      artifact ->
        artifact
    end
  end

  @doc """
  Looks up a surface form in the lexicon for `locale`, returning
  `{combined_mask, pattern_indexes}` or nil.

  """
  def lookup(locale, word) when is_atom(locale) and is_binary(word) do
    case artifact(locale) do
      nil -> nil
      %{lexicon: lexicon} -> lookup_form(lexicon, word)
    end
  end

  # Upstream falls back to the lowercased form for words not found
  # with their original case.
  defp lookup_form(lexicon, word) do
    case Lexicon.lookup(lexicon, word) do
      nil ->
        lowercased = String.downcase(word)
        if lowercased != word, do: Lexicon.lookup(lexicon, lowercased)

      value ->
        value
    end
  end

  # The persistent_term entry for a locale, loading it on first use.
  # Returns nil when the data is not available (rather than raising),
  # so callers that reach here without a prior resolve degrade to a
  # miss instead of crashing.
  defp artifact(locale) do
    case :persistent_term.get({__MODULE__, locale}, nil) do
      nil ->
        case ensure_loaded(locale) do
          :ok -> :persistent_term.get({__MODULE__, locale}, nil)
          {:error, _reason} -> nil
        end

      artifact ->
        artifact
    end
  end

  @impl true
  def init(_options) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:load, locale}, _from, state) do
    if loaded?(locale) do
      {:reply, :ok, state}
    else
      {:reply, load(locale), state}
    end
  end

  defp load(locale) do
    path = Localize.Inflection.DataDir.path("#{locale}.etf")

    with {:ok, binary} <- File.read(path),
         raw = :erlang.binary_to_term(binary),
         %Lexicon{} = lexicon <- Map.get(raw, :lexicon) do
      artifact = %{
        lexicon: lexicon,
        grammeme_names: raw.grammeme_names,
        grammeme_bits: raw.grammeme_bits,
        patterns: raw.patterns,
        pattern_index: raw.pattern_index,
        features: raw.features,
        contractions: MapSet.new(raw.contractions),
        suffix_exemplars: Map.get(raw, :suffix_exemplars, %{}),
        pronouns: Map.get(raw, :pronouns, [])
      }

      :persistent_term.put({__MODULE__, locale}, artifact)
      :ok
    else
      {:error, _reason} = error ->
        error

      # The artifact carries no packed lexicon, so it predates the
      # packed format. Report it rather than raising; the caller turns
      # a bare reason into InflectionDataNotAvailableError.
      _other ->
        {:error, :incompatible_inflection_artifact}
    end
  end
end
