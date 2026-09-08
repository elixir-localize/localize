defmodule Localize.Inflection.PrefixedDisplay do
  @moduledoc false

  # The per-language synthesizers and conformance harnesses are ported
  # from the upstream C++ linguistic rule tables; their branchiness and
  # nesting mirror the reference implementation they are verified
  # against (see guides/inflection.md).
  # credo:disable-for-this-file Credo.Check.Refactor.Nesting

  # Port of the upstream `PrefixedDisplayFunction` shared by
  # Ukrainian and Czech: whole-string dictionary-only inflection
  # with an optional detachable superlative prefix (най/nej).
  # No tokenization, no guessing; failed inflection keeps the
  # original string.

  alias Localize.Inflection.{Dictionary, DisplayValue, Inflector}

  import Bitwise

  @doc """
  Applies constraints to the display value for a locale using
  dictionary inflection only.

  ### Options

  * `:priorities` is the grammeme priority table list.

  * `:extra_feature` is the language's extra constraint feature
    (such as "animacy").

  * `:prefix` is `{prefix_string, matched_pos_grammeme}` for
    superlative prefix splitting, or nil.

  """
  def display_value(locale, display_data, constraints, options) do
    with %DisplayValue{} = display_value <- List.first(display_data),
         display_string when display_string != "" <- display_value.display_string do
      value_constraints = Map.merge(display_value.constraints, constraints)

      display_string =
        if map_size(constraints) > 0 do
          extra = Keyword.get(options, :extra_feature)

          constraint_values =
            for feature <- ["number", "gender", "case", extra],
                feature != nil,
                value = Map.get(constraints, feature),
                value not in [nil, ""],
                do: value

          disambiguation =
            for value <- [Map.get(constraints, "pos")], value not in [nil, ""], do: value

          case inflect_word(locale, display_string, constraint_values, disambiguation, options) do
            {:ok, inflected} -> inflected
            :error -> display_string
          end
        else
          display_string
        end

      %DisplayValue{display_string: display_string, constraints: value_constraints}
    else
      _other -> nil
    end
  end

  defp inflect_word(locale, word, constraint_values, disambiguation, options) do
    word_type = Dictionary.combined_grammemes(locale, word) || 0
    {prefix, word, word_type} = split_prefix(locale, word, word_type, options)

    if word_type != 0 do
      inflect_options = [
        disambiguation: disambiguation,
        priorities: Keyword.get(options, :priorities, []),
        fallback: false
      ]

      case Inflector.inflect(locale, word, word_type, constraint_values, inflect_options) do
        {:ok, inflected} -> {:ok, prefix <> inflected}
        :error -> :error
      end
    else
      :error
    end
  end

  # Superlative prefix splitting: "най"+adjective inflects the
  # adjective and re-attaches the prefix.
  defp split_prefix(locale, word, 0, options) do
    case Keyword.get(options, :prefix) do
      nil ->
        {"", word, 0}

      {prefix, pos_name} ->
        matched_pos = Dictionary.binary_properties(locale, [pos_name]) || 0

        with true <- String.starts_with?(word, prefix) and byte_size(word) > byte_size(prefix),
             rest = binary_part(word, byte_size(prefix), byte_size(word) - byte_size(prefix)),
             grammemes when is_integer(grammemes) <- Dictionary.combined_grammemes(locale, rest),
             true <- (grammemes &&& matched_pos) != 0 do
          {prefix, rest, grammemes}
        else
          _other -> {"", word, 0}
        end
    end
  end

  defp split_prefix(_locale, word, word_type, _options), do: {"", word, word_type}
end
