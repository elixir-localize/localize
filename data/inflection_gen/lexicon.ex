defmodule Localize.Inflection.DataGen.Lexicon do
  @moduledoc false

  # The per-language synthesizers and conformance harnesses are ported
  # from the upstream C++ linguistic rule tables; their branchiness and
  # nesting mirror the reference implementation they are verified
  # against (see guides/inflection.md).
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting

  # Parses the upstream `dictionary_XX.lst` lexical dictionary format.
  #
  # Each line has the form:
  #
  #     surface form: grammeme grammeme … [inflection=<hex-id> …]
  #
  # The surface form may contain spaces. Grammemes are flat property
  # names ("singular", "noun", …). `inflection=` entries reference
  # inflection patterns defined in `inflectional_XX.xml` by their
  # hexadecimal pattern name.

  @doc """
  Streams a `.lst` file, returning a list of
  `{surface, grammeme_names, pattern_names}` tuples.

  """
  def parse_file(path) do
    path
    |> File.stream!()
    |> Enum.reduce_while([], fn line, acc ->
      # A "====" rule ends the dictionary; the remainder of the
      # file is a generation-statistics footer.
      if String.starts_with?(line, "====") do
        {:halt, acc}
      else
        case parse_line(line) do
          nil -> {:cont, acc}
          entry -> {:cont, [entry | acc]}
        end
      end
    end)
    |> Enum.reverse()
  end

  @doc """
  Parses a single `.lst` line into `{surface, grammemes, patterns}`
  or nil for blank lines.

  """
  def parse_line(line) do
    line = String.trim_trailing(line, "\n")

    with false <- line == "",
         [surface, properties] <- String.split(line, ": ", parts: 2) do
      {grammemes, patterns} = split_properties(properties)
      {surface, grammemes, patterns}
    else
      _other -> nil
    end
  end

  defp split_properties(properties) do
    properties
    |> String.split(" ")
    |> Enum.reduce({[], []}, fn
      "inflection=" <> pattern, {grammemes, patterns} ->
        {grammemes, [pattern | patterns]}

      "", acc ->
        acc

      grammeme, {grammemes, patterns} ->
        {[grammeme | grammemes], patterns}
    end)
    |> then(fn {grammemes, patterns} ->
      {Enum.reverse(grammemes), Enum.reverse(patterns)}
    end)
  end
end
