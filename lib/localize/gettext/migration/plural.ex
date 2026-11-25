defmodule Localize.Gettext.Migration.Plural do
  @moduledoc false

  # Turns the forms of a Gettext plural entry into one MF2 `.match`
  # message that chooses as Gettext chooses.
  #
  # Gettext picks a form by the index its plural formula gives a count;
  # MF2 picks a variant by the count's CLDR plural category, or by an exact
  # number key. For each category the index Gettext gives most of its
  # counts becomes the category's variant. A count Gettext gives another
  # index becomes an exact key, as `0` is in a French catalog whose formula
  # is `n != 1`, where CLDR puts 0 and 1 in `one`. Where such counts recur
  # beyond `@exception_limit` the two disagree without end, and the entry
  # cannot be written as categories.

  alias Localize.Number.PluralRule.Cardinal

  @counts Enum.to_list(0..1100) ++ [10_000, 100_000, 1_000_000, 10_000_000]
  @exception_limit 100
  @category_order [:zero, :one, :two, :few, :many]

  # The selector is a `.local`, so each pattern keeps `{$count}` as the
  # unannotated placeholder it was, and formats as it did.
  @selector "$plural_count"

  @doc false
  # `forms` are the strings of the entry by index; `plural_info` is what
  # `Gettext.Plural.init/1` returns for the catalog; `locale` is its
  # validated tag.
  @spec message([String.t()], term(), Localize.LanguageTag.t()) ::
          {:ok, String.t()} | {:error, atom()}
  def message(forms, plural_info, locale) do
    with {:ok, patterns} <- patterns(forms),
         {:ok, choice} <- choice(plural_info, locale, length(patterns)) do
      {:ok, render(choice, patterns)}
    end
  end

  defp patterns(forms) do
    forms
    |> Enum.reduce_while({:ok, []}, fn form, {:ok, acc} -> add_pattern(form, acc) end)
    |> reverse_ok()
  end

  defp add_pattern(form, acc) do
    case pattern(form) do
      {:ok, pattern} -> {:cont, {:ok, [pattern | acc]}}
      :error -> {:halt, {:error, :form_is_mf2}}
    end
  end

  defp reverse_ok({:ok, list}) do
    {:ok, Enum.reverse(list)}
  end

  defp reverse_ok(error) do
    error
  end

  # A form as the body of a quoted pattern. A form that is a complex MF2
  # message cannot be a variant.
  defp pattern(form) do
    source = Localize.Gettext.Migration.__mf2_text__(form)

    cond do
      not String.valid?(source) -> :error
      String.starts_with?(source, "{{") -> {:ok, String.slice(source, 2..-3//1)}
      String.starts_with?(source, ".") -> :error
      true -> {:ok, source}
    end
  end

  # Which index each category takes, the exact counts that differ from
  # their category's, and the index of the fallback variant.
  defp choice(plural_info, locale, form_count) do
    observations =
      Enum.map(@counts, fn count ->
        {count, Cardinal.plural_rule(count, locale), Gettext.Plural.plural(plural_info, count)}
      end)

    by_category = Enum.group_by(observations, &elem(&1, 1), &elem(&1, 2))

    dominant =
      Map.new(by_category, fn {category, indexes} -> {category, most_frequent(indexes)} end)

    exceptions =
      for {count, category, index} <- observations,
          index != dominant[category],
          do: {count, index}

    cond do
      Enum.any?(dominant, fn {_category, index} -> index >= form_count end) ->
        {:error, :too_few_forms}

      Enum.any?(exceptions, fn {count, index} ->
        count >= @exception_limit or index >= form_count
      end) ->
        {:error, :plural_forms_disagree}

      true ->
        {:ok,
         %{dominant: dominant, exceptions: exceptions, fallback: fallback(dominant, by_category)}}
    end
  end

  defp most_frequent(indexes) do
    indexes
    |> Enum.frequencies()
    |> Enum.max_by(fn {index, count} -> {count, -index} end)
    |> elem(0)
  end

  # The `other` category's index where integers reach it, and else that of
  # the category most integers fall in, as `many` in Russian, whose
  # `other` holds fractions alone, which `ngettext` never counts.
  defp fallback(%{other: index}, _by_category) do
    index
  end

  defp fallback(dominant, by_category) do
    {category, _indexes} =
      Enum.max_by(by_category, fn {_category, indexes} -> length(indexes) end)

    dominant[category]
  end

  defp render(choice, patterns) do
    fallback_pattern = Enum.at(patterns, choice.fallback)

    exact =
      for {count, index} <- Enum.sort(choice.exceptions) do
        "#{count} {{#{Enum.at(patterns, index)}}}"
      end

    categories =
      for category <- @category_order,
          index = Map.get(choice.dominant, category),
          not is_nil(index),
          pattern = Enum.at(patterns, index),
          pattern != fallback_pattern do
        "#{category} {{#{pattern}}}"
      end

    Enum.join(
      [".local #{@selector} = {$count :number}", ".match #{@selector}"] ++
        exact ++ categories ++ ["* {{#{fallback_pattern}}}"],
      "\n"
    )
  end
end
