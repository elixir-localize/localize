defmodule Localize.Collation.SortKey do
  # Constructs binary sort keys from processed collation elements.
  #
  # Sort keys are multi-level byte sequences that can be compared with
  # binary comparison (`<`, `>`, `==`) to determine string ordering.
  #
  # Structure: [L1 weights] 0000 [L2 weights] 0000 [L3 weights] [0000 L4 weights]
  #
  @moduledoc false

  import Bitwise

  alias Localize.Collation.{Element, Options}

  @level_separator <<0x00, 0x00>>

  @doc """
  Build a binary sort key from processed collation elements.

  ### Arguments

  * `processed_elements` - a list of `{element, quaternary}` tuples as returned
    by `Localize.Collation.Variable.process/3`.

  * `options` - a `%Localize.Collation.Options{}` struct controlling which levels
    to include.

  * `original_string` - the original input string, used for the identical level
    (default: `nil`).

  ### Returns

  A binary sort key where levels are separated by `<<0x00, 0x00>>`.

  ### Examples

      iex> elements = [{{0x23EC, 0x0020, 0x0008, false}, 0}]
      iex> options = Localize.Collation.Options.new(strength: :primary)
      iex> Localize.Collation.SortKey.build(elements, options)
      <<0x23, 0xEC>>

  """
  @spec build([{Element.t(), non_neg_integer()}], Options.t(), String.t() | nil) :: binary()
  def build(processed_elements, %Options{} = options, original_string \\ nil) do
    key = build_primary(processed_elements)

    key =
      if options.strength in [:secondary, :tertiary, :quaternary, :identical] do
        key <> @level_separator <> build_secondary(processed_elements, options)
      else
        key
      end

    key =
      if options.strength in [:tertiary, :quaternary, :identical] do
        key =
          if options.case_level do
            key <> @level_separator <> build_case_level(processed_elements)
          else
            key
          end

        key <> @level_separator <> build_tertiary(processed_elements, options)
      else
        if options.case_level do
          key <> @level_separator <> build_case_level(processed_elements)
        else
          key
        end
      end

    key =
      if options.strength in [:quaternary, :identical] and options.alternate == :shifted do
        key <> @level_separator <> build_quaternary(processed_elements)
      else
        key
      end

    key =
      if options.strength == :identical do
        nfd =
          if original_string, do: :unicode.characters_to_nfd_binary(original_string), else: <<>>

        key <> @level_separator <> nfd
      else
        key
      end

    key
  end

  defp build_primary(elements) do
    elements
    |> Enum.reduce(<<>>, fn {elem, _q}, acc ->
      p = Element.primary(elem)

      if p > 0 do
        acc <> <<p::16>>
      else
        acc
      end
    end)
  end

  defp build_secondary(elements, options) do
    weights =
      elements
      |> Enum.reduce([], fn {elem, _q}, acc ->
        s = Element.secondary(elem)

        if s > 0 do
          [s | acc]
        else
          acc
        end
      end)
      |> Enum.reverse()

    weights =
      if options.backwards do
        Enum.reverse(weights)
      else
        weights
      end

    weights
    |> Enum.reduce(<<>>, fn w, acc -> acc <> <<w::16>> end)
  end

  defp build_tertiary(elements, options) do
    elements
    |> Enum.reduce(<<>>, fn {elem, _q}, acc ->
      t = apply_case_first(Element.tertiary(elem), options.case_first)

      if t > 0 do
        acc <> <<t::16>>
      else
        acc
      end
    end)
  end

  defp build_case_level(elements) do
    elements
    |> Enum.reduce(<<>>, fn {elem, _q}, acc ->
      if Element.primary(elem) > 0 do
        acc <> <<case_bit(elem)::16>>
      else
        acc
      end
    end)
  end

  defp case_bit(elem) do
    if (Element.tertiary(elem) &&& 0x08) != 0, do: 1, else: 0
  end

  defp build_quaternary(elements) do
    elements
    |> Enum.reduce(<<>>, fn {_elem, q}, acc ->
      if q > 0 do
        acc <> <<q::16>>
      else
        acc
      end
    end)
  end

  defp apply_case_first(tertiary, false), do: tertiary

  defp apply_case_first(tertiary, :upper) do
    case_bit = tertiary &&& 0x08

    if case_bit != 0 do
      tertiary &&& Bitwise.bnot(0x08)
    else
      tertiary ||| 0x08
    end
  end

  defp apply_case_first(tertiary, :lower) do
    tertiary
  end
end
