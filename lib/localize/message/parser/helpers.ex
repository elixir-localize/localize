defmodule Localize.Message.Parser.Helpers do
  @moduledoc false

  # Runtime helper functions called by the pre-compiled parser.
  # These are extracted from the combinator module so the
  # NimbleParsec dependency is not needed at runtime.

  @doc false
  def wrap_escape([char]), do: {:escape, char}

  @doc false
  def to_nfc_string(chars) do
    chars |> List.to_string() |> :unicode.characters_to_nfc_binary()
  end

  @doc false
  def wrap_identifier([name]), do: name
  def wrap_identifier([namespace, name]), do: {:namespace, namespace, name}

  @doc false
  def wrap_quoted_literal(parts) do
    text =
      parts
      |> Enum.map_join(fn
        {:escape, c} -> c
        s when is_binary(s) -> s
      end)
      |> :unicode.characters_to_nfc_binary()

    {:literal, text}
  end

  @doc false
  def wrap_number_literal(parts) do
    text = Enum.join(parts)
    {:number_literal, text}
  end

  @doc false
  def wrap_option([name, value]), do: {:option, name, value}

  @doc false
  def wrap_attribute([name]), do: {:attribute, name, nil}
  def wrap_attribute([name, value]), do: {:attribute, name, value}

  @doc false
  def wrap_function([name | options]), do: {:function, name, options}

  @doc false
  def wrap_expression(parts) do
    {operand, rest} =
      case parts do
        [{tag, _} = op | rest] when tag in [:variable, :literal, :number_literal] -> {op, rest}
        rest -> {nil, rest}
      end

    {func, rest} =
      case rest do
        [{:function, _, _} = f | rest] -> {f, rest}
        rest -> {nil, rest}
      end

    attributes = Enum.filter(rest, &match?({:attribute, _, _}, &1))
    {:expression, operand, func, attributes}
  end

  @doc false
  def wrap_markup_open(parts) do
    [kind | rest] = Enum.reverse(parts)
    [name | opts_and_attrs] = Enum.reverse(rest)
    {options, attributes} = Enum.split_with(opts_and_attrs, &match?({:option, _, _}, &1))

    case kind do
      :standalone -> {:markup_standalone, name, options, attributes}
      :open -> {:markup_open, name, options, attributes}
    end
  end

  @doc false
  def wrap_markup_close([name | opts_and_attrs]) do
    {options, attributes} = Enum.split_with(opts_and_attrs, &match?({:option, _, _}, &1))
    {:markup_close, name, options, attributes}
  end

  @doc false
  def wrap_text(chars), do: {:text, List.to_string(chars)}

  @doc false
  def wrap_quoted_pattern(parts), do: {:quoted_pattern, parts}

  @doc false
  def wrap_input([expr]), do: {:input, expr}

  @doc false
  def wrap_local([var, expr]), do: {:local, var, expr}

  @doc false
  def wrap_variant(parts) do
    {pattern, keys} = List.pop_at(parts, -1)
    {:variant, keys, pattern}
  end

  @doc false
  def wrap_matcher(parts) do
    {selectors, variants} =
      Enum.split_with(parts, fn
        {:variable, _} -> true
        {:variant, _, _} -> false
      end)

    {:match, selectors, variants}
  end

  @doc false
  def wrap_complex(parts) do
    {declarations, [body]} =
      Enum.split_with(parts, fn
        {:input, _} -> true
        {:local, _, _} -> true
        _ -> false
      end)

    {:complex, declarations, body}
  end

  @doc false
  def maybe_wrap_leading_ws(rest, [], context, _line, _offset), do: {rest, [], context}

  def maybe_wrap_leading_ws(rest, chars, context, _line, _offset) do
    text = chars |> Enum.reverse() |> List.to_string()
    {rest, [{:text, text}], context}
  end

  @doc false
  def coalesce_text(rest, acc, context, _line, _offset) do
    coalesced =
      acc
      |> Enum.reverse()
      |> coalesce_text_forward([])

    {rest, coalesced, context}
  end

  defp coalesce_text_forward([], result), do: result

  defp coalesce_text_forward([{:text, t1}, {:text, t2} | rest], result) do
    coalesce_text_forward([{:text, t1 <> t2} | rest], result)
  end

  defp coalesce_text_forward([head | rest], result) do
    coalesce_text_forward(rest, [head | result])
  end
end
