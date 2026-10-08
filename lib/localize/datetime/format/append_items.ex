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

  * `{:ok, pattern}` where `pattern` is the augmented pattern string. When
    no format carries any requested field, the pattern starts from the first
    field in CLDR's canonical order, as CLDR's reference pattern generator
    does.

  * `:error` when a field the pattern would have to append is not one TR35
    names as an append item.

  * `{:error, exception}` if the locale's data cannot be read.

  """
  @spec augment(atom() | String.t(), Localize.locale(), atom(), Keyword.t()) ::
          {:ok, String.t()} | :error | {:error, Exception.t()}
  def augment(skeleton, locale_id, calendar_type, options \\ []) do
    case appendable_subset(skeleton, locale_id, calendar_type) do
      {base_calendar, matched_id, missing_tokens} ->
        base = {matched_id, base_calendar}
        append_to(base, missing_tokens, skeleton, locale_id, calendar_type, options)

      nil ->
        from_fields(skeleton, locale_id, calendar_type)
    end
  end

  # The Chinese and Dangi calendars, which TR35 excepts from the calendars
  # that inherit their date formats (`format_calendars/2`).
  @own_date_formats_alone [:chinese, :dangi]

  @doc false
  # The CLDR calendars whose formats a skeleton is matched against, the
  # calendar's own first. TR35, Calendar Elements: "Non-Gregorian calendars
  # inherit standard time formats (in the `<timeFormats>` element) from the
  # Gregorian calendar in the same locale. Most non-Gregorian calendars
  # (other than Chinese and Dangi) inherit general date format data (in the
  # `<dateFormats>` and `<dateTimeFormats>` elements) from the "generic"
  # calendar format data in the same locale, which in turn inherits from
  # Gregorian." CLDR's data makes the first hop, each such calendar's
  # formats being the generic calendar's, and has no alias for the second,
  # so the Gregorian calendar's formats are asked here, after the calendar's
  # own: a Hebrew date's `yw` is the Gregorian "week 39 of 5786", and its
  # `yMMMdw` the Hebrew `yMMMd` with the week appended. ICU's pattern
  # generator follows the data and writes "5786 (week: 39)".
  #
  # The Chinese and Dangi calendars match a skeleton of date fields against
  # their own formats alone (user, 2026-10-06), TR35 not saying what theirs
  # inherit, and one of time fields against the Gregorian calendar's too, as
  # every calendar's times are.
  @spec format_calendars(atom() | String.t(), atom()) :: [atom(), ...]
  def format_calendars(_skeleton, :gregorian), do: [:gregorian]

  def format_calendars(skeleton, calendar_type) when calendar_type in @own_date_formats_alone do
    if Match.only_fields?(skeleton, :time), do: [calendar_type, :gregorian], else: [calendar_type]
  end

  def format_calendars(_skeleton, calendar_type), do: [calendar_type, :gregorian]

  @doc false
  # A skeleton's pattern in the formats its calendar inherits, the Gregorian
  # calendar's: the format of that name, else the closest with its widths
  # adjusted. `nil` where the calendar inherits none, or none carries the
  # skeleton's fields. `Localize.Date` asks once a calendar's own formats
  # have none.
  @spec inherited_pattern(atom() | String.t(), atom(), atom(), Keyword.t()) ::
          {:ok, String.t()} | nil
  def inherited_pattern(skeleton, locale_id, calendar_type, options \\ []) do
    [_its_own | inherited] = format_calendars(skeleton, calendar_type)
    Enum.find_value(inherited, &single_format(skeleton, locale_id, &1, options))
  end

  # One calendar's format for a skeleton: the one of that name, or the
  # closest with the same fields.
  defp single_format(skeleton, locale_id, calendar_type, options) do
    available_pattern(skeleton, locale_id, calendar_type, options) ||
      matched_pattern_for(skeleton, locale_id, calendar_type, options)
  end

  # CLDR's field order, which its reference pattern generator builds a
  # fallback in.
  @canonical_order ~w(G y Y u U r Q q M L w W E e c d D F g a b B h H K k m s S A z Z O v V X x)

  # The last resort, where no available format carries any of the requested
  # fields: `en` has no format for an era alone, so `:G` has nothing to
  # match. CLDR's reference pattern generator starts from the first field in
  # its canonical order, written as itself, and appends the rest, so `:G`
  # renders "AD" and `:QQQQ` "3rd quarter". A field TR35 does not name as an
  # append item still leaves the skeleton unresolvable, and so does a zone
  # alone: `Localize.DateTime` formats one as its own pattern, and a date or
  # a time has no zone to show.
  defp from_fields(skeleton, locale_id, calendar_type) do
    with {:ok, tokens} <- Match.tokenize_skeleton(skeleton),
         [{symbol, count} | rest] <- Enum.sort_by(tokens, &canonical_index/1),
         true <- Enum.all?(tokens, &appendable?/1),
         false <- Match.zone_only_skeleton?(skeleton),
         {:ok, templates} <- Format.append_items(locale_id, calendar_type) do
      append_all(String.duplicate(symbol, count), rest, templates, locale_id)
    else
      {:error, _reason} = error -> error
      _unresolvable -> :error
    end
  end

  defp canonical_index({symbol, _count}) do
    Enum.find_index(@canonical_order, &(&1 == symbol)) || length(@canonical_order)
  end

  # The closest subset match among the formats the calendar has and the
  # ones it inherits, but only where every field it lacks is one TR35 names
  # as an append item. TR35 takes "the one with the greatest number of
  # matching fields (but no extra fields)", so the one lacking the fewest:
  # a Hebrew `ywE` takes the Gregorian `yw`, two of its fields, before a
  # Hebrew format of the year alone. Of two that lack as many, the
  # calendar's own stands before one it inherits, as an item does in
  # inheritance, so `yMMMdw` is appended to the Hebrew `yMMMd` and reads as
  # that date does alone.
  defp appendable_subset(skeleton, locale_id, calendar_type) do
    skeleton
    |> format_calendars(calendar_type)
    |> Enum.flat_map(&subset_in(skeleton, locale_id, &1))
    |> Enum.min_by(fn {_calendar, _matched_id, missing} -> Enum.count(missing) end, fn -> nil end)
  end

  defp subset_in(skeleton, locale_id, calendar) do
    with {:ok, matched_id, missing_tokens} <- Match.subset_match(skeleton, locale_id, calendar),
         true <- Enum.all?(missing_tokens, &appendable?/1) do
      [{calendar, matched_id, missing_tokens}]
    else
      _not_appendable -> []
    end
  end

  # The matched format is its own calendar's, and the fields it lacks are
  # appended with the templates of the calendar asked for.
  defp append_to(base, missing_tokens, skeleton, locale_id, calendar_type, options) do
    {matched_id, base_calendar} = base

    with {:ok, pattern} <- matched_pattern(matched_id, locale_id, base_calendar, options),
         {:ok, adjusted} <- adjust_to_match(pattern, skeleton, missing_tokens, matched_id),
         {:ok, templates} <- Format.append_items(locale_id, calendar_type) do
      append_all(adjusted, missing_tokens, templates, locale_id)
    end
  end

  @doc """
  Resolves a skeleton to a pattern, using the append-item path when no
  available format carries every requested field.

  This is the whole resolution chain in one call: an exact available
  format, else the closest match with its field widths adjusted to the
  request, in the calendar's own formats and then in the Gregorian
  calendar's, which TR35 has most calendars inherit; else a subset match
  from either, augmented with append items.

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
  @spec resolve_pattern(atom() | String.t(), Localize.locale(), atom(), Keyword.t()) ::
          {:ok, String.t()} | :error | {:error, Exception.t()}
  def resolve_pattern(skeleton, locale_id, calendar_type, options \\ []) do
    # Three sources in TR35's order, the first two asked of each calendar
    # whose formats the skeleton is matched against (`format_calendars/2`).
    # They return `nil` when they have nothing, so the next is asked; only
    # the last reports failure.
    skeleton
    |> format_calendars(calendar_type)
    |> Enum.find_value(&single_format(skeleton, locale_id, &1, options))
    |> case do
      nil -> augment(skeleton, locale_id, calendar_type, options)
      {:ok, _pattern} = resolved -> resolved
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
         {:ok, adjusted} <- Match.adjust_field_lengths(pattern, tokens, matched_id) do
      {:ok, adjusted}
    else
      _no_single_match -> nil
    end
  end

  # A skeleton that names no known format is not an error here — it just
  # means the match path is the one to take. Only an existing atom is
  # looked up, so an unknown skeleton cannot mint one.
  defp existing_format_id(skeleton) when is_atom(skeleton), do: skeleton

  defp existing_format_id(skeleton) when is_binary(skeleton) do
    Localize.Utils.Helpers.existing_atom(skeleton)
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
          resolved_variant(variants, options)

        _no_pattern ->
          :error
      end
    end
  end

  defp resolved_variant(variants, options) do
    case Format.resolve_variant(variants, options) do
      pattern when is_binary(pattern) -> {:ok, pattern}
      _no_variant -> :error
    end
  end

  # The matched pattern still has to take the widths the caller asked for,
  # but only for the fields it carries — a missing field's width belongs to
  # the appended part, not to the base. The matched id lets a width the id
  # already asks for stand, as TR35 rule 2 has it.
  defp adjust_to_match(pattern, skeleton, missing_tokens, matched_id) do
    with {:ok, tokens} <- Match.tokenize_skeleton(skeleton) do
      missing = Enum.map(missing_tokens, &elem(&1, 0))
      kept = Enum.reject(tokens, fn {symbol, _count} -> symbol in missing end)
      Match.adjust_field_lengths(pattern, kept, matched_id)
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

  @doc false
  # TR35 §Missing Skeleton Fields, step 3. Two append items are glue rather
  # than a single field: `Date-Timezone` joins a date to a zone when the time
  # half of a split request is only a zone, and `Time-Day-Of-Week` joins a
  # time to a weekday when the date half is only a weekday. Each puts `{0}`
  # and `{1}` where its own template writes them and carries no `{2}`, so the
  # arguments are named for the template's placeholders, not for date/time.
  @spec glue(
          :date_timezone | :time_day_of_week,
          String.t(),
          String.t(),
          Localize.locale(),
          atom()
        ) ::
          {:ok, String.t()} | :error
  def glue(kind, zero, one, locale_id, calendar_type) do
    with {:ok, templates} <- Format.append_items(locale_id, calendar_type),
         template when is_list(template) <- Map.get(templates, kind) do
      {:ok,
       Enum.map_join(template, "", fn
         0 -> zero
         1 -> one
         literal when is_binary(literal) -> literal
         _other -> ""
       end)}
    else
      _no_template -> :error
    end
  end

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
