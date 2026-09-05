defmodule Localize.DateTime.Format.AppendItems do
  @moduledoc """
  TR35's append-item path for flexible date-time patterns.

  A locale ships a finite set of available formats, so a skeleton may ask
  for a field combination CLDR does not carry. TR35 resolves this by
  matching the closest format that *is* available and then appending each
  requested field the match omits, using the locale's `appendItems`
  templates. English asking for `:yMMMdQ` matches `yMMMd` and appends the
  quarter as "Jul 6, 2024 (quarter: Q3)".

  Each template is a substitution list where `0` is the matched pattern,
  `1` is the missing field's own pattern, and `2` is the field's localized
  display name. Fields are appended one at a time, each round's output
  becoming the next round's `{0}`.

  """

  alias Localize.DateTime.Format
  alias Localize.DateTime.Format.Match

  # TR35 keys append items by field name while skeletons use pattern
  # symbols. Day period has no append item of its own: CLDR expects it to
  # travel with the hour, and a locale that omits it falls back to a plain
  # space join.
  #
  # Fractional seconds (`S`) and milliseconds-in-day (`A`) are deliberately
  # absent. A fraction attaches to a seconds field rather than standing as
  # an item of its own, so `:hmSS` — a fraction with no seconds to attach
  # to — stays unresolvable instead of gaining a "(second: 34)" suffix.
  @symbol_to_field %{
    "G" => :era,
    "y" => :year,
    "Y" => :year,
    "u" => :year,
    "U" => :year,
    "r" => :year,
    "Q" => :quarter,
    "q" => :quarter,
    "M" => :month,
    "L" => :month,
    "w" => :week,
    "W" => :week,
    "d" => :day,
    "D" => :day,
    "F" => :day,
    "g" => :day,
    "E" => :day_of_week,
    "e" => :day_of_week,
    "c" => :day_of_week,
    "a" => :day_period,
    "b" => :day_period,
    "B" => :day_period,
    "h" => :hour,
    "H" => :hour,
    "K" => :hour,
    "k" => :hour,
    "m" => :minute,
    "s" => :second,
    "v" => :timezone,
    "V" => :timezone,
    "z" => :timezone,
    "Z" => :timezone,
    "O" => :timezone,
    "X" => :timezone,
    "x" => :timezone
  }

  # `append_items` and `date_fields` name the same field differently, so the
  # `{2}` display name is looked up through this bridge.
  @field_to_display_field %{
    day_of_week: :weekday,
    time_day_of_week: :weekday,
    timezone: :zone,
    date_timezone: :zone
  }

  @doc false
  @spec symbol_to_field(String.t()) :: atom() | nil
  def symbol_to_field(symbol), do: Map.get(@symbol_to_field, symbol)

  @doc """
  Resolves a skeleton no available format covers by augmenting the closest
  subset match with append-item templates.

  ### Arguments

  * `skeleton` is the requested skeleton, an atom or a string.

  * `locale_id` is a resolved locale identifier.

  * `calendar_type` is a CLDR calendar name.

  * `options` are the formatting options, used to resolve pattern variants.

  ### Returns

  * `{:ok, pattern}` where `pattern` is the augmented pattern string.

  * `:error` when no format is a subset of the request, or when a field it
    lacks is not one TR35 names as an append item.

  * `{:error, exception}` if the locale's data cannot be read.

  """
  @spec augment(atom() | String.t(), atom(), atom(), Keyword.t()) ::
          {:ok, String.t()} | :error | {:error, Exception.t()}
  def augment(skeleton, locale_id, calendar_type, options \\ []) do
    case appendable_subset(skeleton, locale_id, calendar_type) do
      {matched_id, missing_tokens} ->
        append_to(matched_id, missing_tokens, skeleton, locale_id, calendar_type, options)

      nil ->
        :error
    end
  end

  # The closest subset match, but only when every field it lacks is one
  # TR35 names as an append item.
  defp appendable_subset(skeleton, locale_id, calendar_type) do
    with {:ok, matched_id, missing_tokens} <-
           Match.subset_match(skeleton, locale_id, calendar_type),
         true <- Enum.all?(missing_tokens, &appendable?/1) do
      {matched_id, missing_tokens}
    else
      _not_appendable -> nil
    end
  end

  defp append_to(matched_id, missing_tokens, skeleton, locale_id, calendar_type, options) do
    with {:ok, base} <- matched_pattern(matched_id, locale_id, calendar_type, options),
         {:ok, adjusted} <- adjust_to_match(base, skeleton, missing_tokens),
         {:ok, templates} <- Format.append_items(locale_id, calendar_type) do
      append_all(adjusted, missing_tokens, templates, locale_id)
    end
  end

  @doc """
  Resolves a skeleton to a pattern, using the append-item path when no
  available format carries every requested field.

  This is the whole resolution chain in one call: an exact available
  format, else the closest match with its field widths adjusted to the
  request, else a subset match augmented with append items.

  ### Arguments

  * `skeleton` is the requested skeleton, an atom or a string.

  * `locale_id` is a resolved locale identifier.

  * `calendar_type` is a CLDR calendar name.

  * `options` are the formatting options, used to resolve pattern variants.

  ### Returns

  * `{:ok, pattern}`.

  * `:error` when the skeleton cannot be resolved at all.

  * `{:error, exception}` if the locale's data cannot be read.

  """
  @spec resolve_pattern(atom() | String.t(), atom(), atom(), Keyword.t()) ::
          {:ok, String.t()} | :error | {:error, Exception.t()}
  def resolve_pattern(skeleton, locale_id, calendar_type, options \\ []) do
    # Three sources in TR35's order. The first two return `nil` when they
    # have nothing, so the next is asked; only the last reports failure.
    with nil <- available_pattern(skeleton, locale_id, calendar_type, options),
         nil <- matched_pattern_for(skeleton, locale_id, calendar_type, options) do
      augment(skeleton, locale_id, calendar_type, options)
    end
  end

  # The locale's own format for this exact skeleton, or `nil` if it ships
  # none — which is the common case, not a failure.
  defp available_pattern(skeleton, locale_id, calendar_type, options) do
    with {:ok, available} <- Format.available_formats(locale_id, calendar_type),
         id when not is_nil(id) <- existing_format_id(skeleton),
         pattern when not is_nil(pattern) <- Map.get(available, id),
         {:ok, resolved} <- variant_pattern(pattern, options) do
      {:ok, resolved}
    else
      _no_format_of_its_own -> nil
    end
  end

  # The closest single format, its field widths adjusted to the request.
  defp matched_pattern_for(skeleton, locale_id, calendar_type, options) do
    with {:ok, matched_id} when is_atom(matched_id) <-
           Match.best_match(skeleton, locale_id, calendar_type),
         {:ok, pattern} <- matched_pattern(matched_id, locale_id, calendar_type, options),
         {:ok, tokens} <- Match.tokenize_skeleton(Kernel.to_string(skeleton)),
         {:ok, adjusted} <- Match.adjust_field_lengths(pattern, tokens) do
      {:ok, adjusted}
    else
      _no_single_match -> nil
    end
  end

  # A skeleton that names no known format is not an error here — it just
  # means the match path is the one to take. `String.to_existing_atom/1`
  # keeps an unknown skeleton from minting an atom.
  defp existing_format_id(skeleton) when is_atom(skeleton), do: skeleton

  defp existing_format_id(skeleton) when is_binary(skeleton) do
    String.to_existing_atom(skeleton)
  rescue
    ArgumentError -> nil
  end

  defp variant_pattern(pattern, _options) when is_binary(pattern), do: {:ok, pattern}

  defp variant_pattern(%{} = variants, options) do
    case Format.resolve_variant(variants, options) do
      pattern when is_binary(pattern) -> {:ok, pattern}
      _no_variant -> :error
    end
  end

  defp variant_pattern(_pattern, _options), do: :error

  # Only a field TR35 names as an append item can be appended. A symbol
  # outside the table — a fractional second — leaves the skeleton
  # unresolvable rather than being tacked on as a parenthesised item.
  defp appendable?({symbol, _count}), do: Map.has_key?(@symbol_to_field, symbol)

  # The matched format's own pattern, with any variant resolved the way the
  # ordinary skeleton path resolves it.
  defp matched_pattern(matched_id, locale_id, calendar_type, options) do
    with {:ok, available} <- Format.available_formats(locale_id, calendar_type) do
      case Map.get(available, matched_id) do
        pattern when is_binary(pattern) ->
          {:ok, pattern}

        %{} = variants ->
          case Format.resolve_variant(variants, options) do
            pattern when is_binary(pattern) -> {:ok, pattern}
            _no_variant -> :error
          end

        _no_pattern ->
          :error
      end
    end
  end

  # The matched pattern still has to take the widths the caller asked for,
  # but only for the fields it carries — a missing field's width belongs to
  # the appended part, not to the base.
  defp adjust_to_match(pattern, skeleton, missing_tokens) do
    with {:ok, tokens} <- Match.tokenize_skeleton(skeleton) do
      missing = Enum.map(missing_tokens, &elem(&1, 0))
      kept = Enum.reject(tokens, fn {symbol, _count} -> symbol in missing end)
      Match.adjust_field_lengths(pattern, kept)
    end
  end

  defp append_all(pattern, missing_tokens, templates, locale_id) do
    appended =
      Enum.reduce(missing_tokens, pattern, fn {symbol, count}, acc ->
        append_one(acc, symbol, count, templates, locale_id)
      end)

    {:ok, appended}
  end

  defp append_one(pattern, symbol, count, templates, locale_id) do
    field = Map.get(@symbol_to_field, symbol)
    field_pattern = String.duplicate(symbol, count)

    case template_for(field, templates) do
      # TR35 leaves a field with no template to a plain space join, which is
      # what CLDR's own root fallback amounts to.
      nil -> pattern <> " " <> field_pattern
      template -> substitute(template, pattern, field_pattern, field, locale_id)
    end
  end

  defp template_for(nil, _templates), do: nil
  defp template_for(field, templates), do: Map.get(templates, field)

  # Integers in the template are the placeholders; everything else is a
  # literal. `{1}` is a pattern fragment, so it is quoted only if the
  # display name it sits beside would otherwise be read as pattern symbols.
  defp substitute(template, matched, field_pattern, field, locale_id) do
    Enum.map_join(template, "", fn
      0 -> matched
      1 -> field_pattern
      2 -> display_name(field, locale_id)
      literal when is_binary(literal) -> literal
    end)
  end

  # A display name is literal text inside a pattern, so it is quoted to keep
  # its letters from being read as field symbols. `en`'s "day of the week"
  # would otherwise format as a date.
  defp display_name(field, locale_id) do
    display_field = Map.get(@field_to_display_field, field, field)

    case Format.field_display_name(locale_id, display_field) do
      {:ok, name} -> quote_literal(name)
      :error -> ""
    end
  end

  defp quote_literal(text) do
    if String.match?(text, ~r/[A-Za-z]/) do
      "'" <> String.replace(text, "'", "''") <> "'"
    else
      text
    end
  end
end
