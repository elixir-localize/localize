defmodule Localize.GuidesExamplesTest do
  @moduledoc """
  Executes every `iex>` example in the README and the guides.

  Those files carry more example code than the module docs do — 600-odd
  examples — and none of it is reachable by `doctest`. The definition-of-done
  process validates them by hand before a release; this makes the same check a
  gate so a stale example is caught when it goes stale rather than months later.

  This deliberately does **not** use `doctest_file/1`. Making that compile
  would mean restructuring the guides so no binding crosses a block or fence
  boundary, which is rewriting correct, readable documents to suit a tool.

  """

  use ExUnit.Case, async: false

  # Examples that cannot run here, with the reason. Each entry is matched as a
  # prefix of the expression. Anything failing that is *not* listed fails the
  # suite.
  @cannot_run [
    # Other packages, referenced to show how the ecosystem fits together.
    {"Money.", "ex_money is not a dependency of Localize"},
    {"Calendrical", "calendrical depends on Localize, so cannot be a dependency of it"},
    {"Localize.PersonName", "localize_person_names is a separate package"},
    {"Localize.Locale.gettext_locale_id(:en, MyApp.Gettext)",
     "needs a host application's Gettext backend"},
    {"MyApp.", "illustrative host-application module"},
    {"Options.validate_options", "shown unaliased, for readability of the surrounding prose"},
    # Requires a custom unit registered by a preceding narrative step that is
    # not itself an example.
    {"Localize.Unit.new(10, \"baume\")", "depends on a custom unit defined in prose above"},
    {":observer.start()", "observer is not available in a headless test run"},
    # `Localize.Unit.parse/2` examples document the *equivalent constructor
    # call* rather than the literal struct, which reads better and is not
    # machine-comparable.
    {"Localize.Unit.parse(", "documented as an equivalent expression, not a literal"},
    # Bound by an example that is itself excused above.
    {", options)", "uses a binding from an excused example"},
    {"Localize.Nif.available?()", "depends on whether this build compiled the NIF"},
    {"Localize.Unit.convert(unit,", "uses a binding from an excused example"},
    {"density.value", "uses a binding from an excused example"},
    {"meters.value", "uses a binding from an excused example"},
    {"converted.value", "uses a binding from an excused example"},
    # Inspect orders map keys by term order, not by the order a guide lists
    # them, so an elided map cannot be prefix-matched.
    {"Localize.Territory.info(:US)", "elided map; inspect key order differs from the guide"}
  ]

  @doc false
  def extract(path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.reduce({[], nil, nil}, &classify/2)
    |> flush()
    |> Enum.reverse()
  end

  # Walks the file a line at a time, accumulating {examples, expression,
  # documented result}. A line either starts a new example, continues one,
  # contributes to its documented result, or ends it.
  defp classify(line, {acc, current, documented}) do
    trimmed = String.trim(line)

    cond do
      String.starts_with?(line, "iex>") ->
        {flush({acc, current, documented}), strip(line, "iex>"), nil}

      current && String.starts_with?(line, "...>") ->
        {acc, current <> "\n" <> strip(line, "...>"), nil}

      current && continues_result?(trimmed) ->
        {acc, current, join(documented, trimmed)}

      true ->
        {flush({acc, current, documented}), nil, nil}
    end
  end

  defp continues_result?(trimmed) do
    trimmed != "" and not String.starts_with?(trimmed, "```")
  end

  defp strip(line, prompt), do: line |> String.trim_leading(prompt) |> String.trim()

  defp join(nil, trimmed), do: trimmed
  defp join(documented, trimmed), do: documented <> "\n" <> trimmed

  defp flush({acc, nil, _documented}), do: acc
  defp flush({acc, current, documented}), do: [{current, documented} | acc]

  # A documented value may elide a long tail with `...`, as
  # `{:ok, [:AT, :BE, :CY, ...]}` does. That is a deliberate documentation
  # choice, so compare only the part before the ellipsis.
  defp evaluate(expression, documented, bad, n, binding) do
    {value, binding} = Code.eval_string(expression, binding, __ENV__)
    actual = inspect(value, limit: :infinity, printable_limit: :infinity)

    if is_nil(documented) or matches?(value, actual, documented) do
      {bad, n + 1, binding}
    else
      {[{expression, documented, actual} | bad], n + 1, binding}
    end
  rescue
    error -> {[{expression, documented, Exception.message(error)} | bad], n + 1, binding}
  catch
    _kind, thrown -> {[{expression, documented, inspect(thrown)} | bad], n + 1, binding}
  end

  defp matches?(actual_value, actual_text, documented) do
    if String.contains?(documented, "...") do
      # A documented value may elide a long tail, as `{:ok, [:AT, :BE, ...]}`
      # does. Compare only up to the ellipsis.
      [prefix | _rest] = String.split(documented, "...", parts: 2)
      String.starts_with?(normalise(actual_text), normalise(prefix))
    else
      # Compare the *terms*. `[text: "here"]` and `[{:text, "here"}]` are the
      # same value written two ways, and only a term comparison knows that.
      # Map key order and whitespace stop mattering too.
      case term(documented) do
        {:ok, value} -> value === actual_value
        :error -> normalise(actual_text) == normalise(documented)
      end
    end
  end

  defp term(text) do
    {value, _binding} = Code.eval_string(text, [], __ENV__)
    {:ok, value}
  rescue
    _error -> :error
  catch
    _kind, _thrown -> :error
  end

  # A guide may write a codepoint as `\\uXXXX` while `inspect/1` emits either
  # `\\x{XXXX}` or the character itself. Decode every notation to the character
  # so the three spellings compare equal.
  defp normalise(string) do
    string
    |> decode_escapes(~r/\\u([0-9A-Fa-f]{4})/)
    |> decode_escapes(~r/\\x\{([0-9A-Fa-f]+)\}/)
    |> String.replace(~r/\s+/, "")
  end

  defp decode_escapes(string, pattern) do
    Regex.replace(pattern, string, fn _whole, hex ->
      <<String.to_integer(hex, 16)::utf8>>
    end)
  end

  defp excused?(expression) do
    Enum.find(@cannot_run, fn {prefix, _why} -> String.contains?(expression, prefix) end)
  end

  for path <- ["README.md" | Path.wildcard("guides/*.md")] do
    @path path

    test "every example in #{path} still produces what it documents" do
      examples = extract(@path)

      # Examples in a file run in sequence and may bind for the next one,
      # exactly as a doctest block does.
      Localize.put_locale(Localize.default_locale())

      {failures, checked, _binding} =
        Enum.reduce(examples, {[], 0, []}, fn {expression, documented}, {bad, n, binding} ->
          if excused?(expression) do
            {bad, n, binding}
          else
            evaluate(expression, documented, bad, n, binding)
          end
        end)

      assert failures == [],
             "#{@path}: #{length(failures)} of #{checked} examples no longer match.\n\n" <>
               Enum.map_join(Enum.reverse(failures), "\n\n", fn {expression, documented, actual} ->
                 "  iex> #{expression}\n  documented: #{inspect(documented)}\n  actual:     #{String.slice(actual, 0, 200)}"
               end)
    end
  end
end
