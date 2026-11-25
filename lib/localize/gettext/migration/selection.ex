defmodule Localize.Gettext.Migration.Selection do
  @moduledoc false

  # Chooses the catalog entries `mix localize.gettext.mf2` may convert: an
  # entry is converted only where every lookup of it changes with it.
  #
  # * A call whose domain is an expression may look up any msgid of any
  #   domain, so no entry is converted.
  #
  # * A call in a domain whose msgid or context is an expression, as in a
  #   `translate_error/1` that translates Ecto's messages, may look up any
  #   msgid of that domain, so none of its entries is converted, unless the
  #   domain is trusted: its dynamic lookups receive only msgids written in
  #   calls in the converted source, as `gettext_noop` writes them.
  #
  # * Otherwise an entry is converted when every source file its `#:`
  #   references name is among the converted ones, or, with no references,
  #   when a call in the converted source looks it up.

  @doc false
  @spec select(
          [{String.t(), Expo.Messages.t(), term()}],
          [{String.t(), map()}],
          [String.t()],
          String.t(),
          [String.t()]
        ) ::
          %{only: %{String.t() => MapSet.t()}, notes: [tuple()]}
  def select(catalogs, lookups, source_directories, root, trusted \\ []) do
    directories = Enum.map(source_directories, &(Path.expand(&1) <> "/"))
    root = Path.expand(root)
    dynamic_domains = for {file, %{domain: :dynamic} = lookup} <- lookups, do: {file, lookup.line}
    unsafe = Map.drop(unsafe_domains(lookups), trusted)
    literal = literal_keys(lookups)

    by_domain = Enum.group_by(catalogs, fn {path, _catalog, _locale} -> domain(path) end)

    {only, outside_notes} =
      Enum.map_reduce(by_domain, [], fn {domain, domain_catalogs}, notes ->
        if match?([_ | _], dynamic_domains) or Map.has_key?(unsafe, domain) do
          {{domain, MapSet.new()}, notes}
        else
          {keys, outside} = domain_keys(domain, domain_catalogs, literal, directories, root)
          {{domain, keys}, outside_note(domain, outside, notes)}
        end
      end)

    notes =
      Enum.map(dynamic_domains, fn {file, line} -> {:dynamic_domain, file, line} end) ++
        Enum.map(unsafe, fn {domain, {file, line}} -> {:dynamic_lookup, domain, file, line} end) ++
        Enum.reverse(outside_notes)

    %{only: Map.new(only), notes: notes}
  end

  @doc false
  @spec domain(String.t()) :: String.t()
  def domain(path) do
    Path.basename(path, Path.extname(path))
  end

  # Each domain with a lookup whose msgid or context is an expression, and
  # the first such lookup.
  defp unsafe_domains(lookups) do
    for {file, %{domain: domain} = lookup} <- lookups,
        is_binary(domain),
        lookup.msgid == :dynamic or lookup.context == :dynamic,
        reduce: %{} do
      unsafe -> Map.put_new(unsafe, domain, {file, lookup.line})
    end
  end

  defp literal_keys(lookups) do
    for {_file, %{domain: domain, context: msgctxt, msgid: msgid}} <- lookups,
        :dynamic not in [domain, msgctxt, msgid],
        into: MapSet.new(),
        do: {domain, msgctxt, msgid}
  end

  # The entries of a domain whose references, in every catalog of the
  # domain, all name converted source, and the number that do not.
  defp domain_keys(domain, catalogs, literal, directories, root) do
    references =
      for {_path, catalog, _locale} <- catalogs,
          message <- catalog.messages,
          reduce: %{} do
        acc -> Map.update(acc, entry_key(message), [paths(message)], &[paths(message) | &1])
      end

    Enum.reduce(references, {MapSet.new(), 0}, fn {key, path_lists}, {keys, outside} ->
      case entry_state(domain, key, path_lists, literal, directories, root) do
        :convert -> {MapSet.put(keys, key), outside}
        :outside -> {keys, outside + 1}
        :unused -> {keys, outside}
      end
    end)
  end

  defp entry_state(domain, {msgctxt, msgid} = _key, path_lists, literal, directories, root) do
    paths = List.flatten(path_lists)

    cond do
      not Enum.all?(paths, &inside?(&1, directories, root)) -> :outside
      match?([_ | _], paths) -> :convert
      MapSet.member?(literal, {domain, msgctxt, msgid}) -> :convert
      true -> :unused
    end
  end

  defp inside?(path, directories, root) do
    expanded = Path.expand(path, root)
    Enum.any?(directories, &String.starts_with?(expanded, &1))
  end

  defp outside_note(_domain, 0, notes) do
    notes
  end

  defp outside_note(domain, count, notes) do
    [{:outside, domain, count} | notes]
  end

  defp entry_key(message) do
    msgctxt =
      if is_nil(message.msgctxt) do
        nil
      else
        IO.iodata_to_binary(message.msgctxt)
      end

    {msgctxt, IO.iodata_to_binary(message.msgid)}
  end

  # The source files a message's `#:` references name, without their line
  # numbers.
  defp paths(message) do
    message.references
    |> List.flatten()
    |> Enum.map(&reference_path/1)
  end

  defp reference_path({path, _line}) do
    path
  end

  defp reference_path(reference) when is_binary(reference) do
    String.replace(reference, ~r/:\d+\z/, "")
  end
end
