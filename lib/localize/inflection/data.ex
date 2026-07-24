defmodule Localize.Inflection.Data do
  @moduledoc false

  # Loads per-locale data artifacts on demand.
  #
  # The lexicon is stored in an ETS table per locale (keyed by
  # surface form). Everything else (grammeme registry, inflection
  # patterns, features, contractions) is stored in `:persistent_term`.
  #
  # A GenServer serializes loading so concurrent first requests for
  # the same locale load the artifact only once.

  use GenServer

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
  Returns the loaded metadata for `locale` (everything except the
  lexicon), raising if the locale is not loaded and cannot be
  loaded.

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

      metadata ->
        metadata
    end
  end

  @doc """
  Looks up a surface form in the lexicon for `locale`, returning
  `{combined_mask, pattern_indexes}` or nil.

  """
  def lookup(locale, word) when is_atom(locale) and is_binary(word) do
    unless loaded?(locale), do: ensure_loaded(locale)

    case :ets.lookup(table_name(locale), word) do
      [{^word, mask, patterns}] ->
        {mask, patterns}

      [] ->
        # Upstream falls back to the lowercased form for words not
        # found with their original case.
        lowercased = String.downcase(word)

        with true <- lowercased != word,
             [{^lowercased, mask, patterns}] <- :ets.lookup(table_name(locale), lowercased) do
          {mask, patterns}
        else
          _other -> nil
        end
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

    with {:ok, binary} <- File.read(path) do
      artifact = :erlang.binary_to_term(binary)
      table = :ets.new(table_name(locale), [:named_table, :set, :public, read_concurrency: true])
      :ets.insert(table, artifact.lexicon)

      metadata = %{
        grammeme_names: artifact.grammeme_names,
        grammeme_bits: artifact.grammeme_bits,
        patterns: artifact.patterns,
        pattern_index: artifact.pattern_index,
        features: artifact.features,
        contractions: MapSet.new(artifact.contractions),
        suffix_exemplars: Map.get(artifact, :suffix_exemplars, %{})
      }

      :persistent_term.put({__MODULE__, locale}, metadata)
      :ok
    end
  end

  defp table_name(locale) do
    # Table names are created from the fixed set of supported locales.
    String.to_atom("unicode_inflection_" <> Atom.to_string(locale))
  end
end
