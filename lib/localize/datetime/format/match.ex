defmodule Localize.DateTime.Format.Match do
  @moduledoc false

  # Implements best match for a requested skeleton to an available format ID.
  #
  # A "best match" from requested skeleton to format ID is found using
  # a closest distance match. Symbols representing the same type
  # (year, month, day, etc.) are compared and the candidate with
  # the smallest total distance is selected.
  #
  # # best_match/3
  #
  # Finds the best matching format ID for a requested skeleton.
  #
  # ### Arguments
  #
  # * `skeleton` is a string or atom composed of format fields.
  #
  # * `locale_id` is a locale identifier atom.
  #
  # * `calendar_type` is a CLDR calendar type atom. Default `:gregorian`.
  #
  # ### Returns
  #
  # * `{:ok, format_id}` or
  #
  # * `{:ok, {date_format_id, time_format_id}}` for combined skeletons.
  #
  # * `{:error, exception}`.

  alias Localize.DateTime.Format

  @date_symbols ~w(G y Y u U r Q q M L W w d D F g E e c)
  # `j`, `J` and `C` are TR35's input-skeleton hour symbols and `A` is the
  # milliseconds in the day, so a split keeps them with the time.
  @time_symbols ~w(h H k K j J C m s S A v V z Z x X O a b B)

  @hour ["k", "h", "K", "H"]
  @hour_12 ["h", "K"]
  @hour_24 ["H", "k"]
  @day_period ["a", "b", "B"]
  # Each list is one field to TR35, whichever symbol spells it: the format
  # and stand-alone forms of a month, a quarter and a weekday, and `e`, the
  # weekday that also has a numeric form. `en` answers `E` with "ccc", so a
  # request for `EEEE` has to find that `c`.
  @month ["L", "M"]
  @quarter ["Q", "q"]
  @day_of_week ["c", "E", "e"]
  @time_zone ["x", "X", "v", "V", "z", "Z", "O"]
  # The year symbols are one field too, though they count differently: `Y`
  # is the week-based year, `u` the extended year, `r` the related Gregorian
  # year and `U` the cyclic year name, numeric where a calendar has none.
  @year ["y", "Y", "u", "U", "r"]

  # Symbols with no numeric form (TR35): every width is text, so a
  # width difference is never a numeric-vs-alpha type mismatch.
  @always_alpha ["E", "a", "b", "B", "G", "x", "X", "v", "V", "z", "Z", "O"]

  # TR35 §Missing Skeleton Fields ranks fields in this order when two
  # formats with missing fields are otherwise equally close: year, month,
  # day, era, week, quarter and weekday, then hour, minute, second, period
  # and zone.
  @field_ranks %{
    "y" => 0,
    "Y" => 0,
    "u" => 0,
    "U" => 0,
    "r" => 0,
    "M" => 1,
    "L" => 1,
    "d" => 2,
    "D" => 2,
    "F" => 2,
    "g" => 2,
    "G" => 3,
    "w" => 4,
    "W" => 4,
    "Q" => 5,
    "q" => 5,
    "E" => 6,
    "e" => 6,
    "c" => 6,
    "h" => 7,
    "H" => 7,
    "K" => 7,
    "k" => 7,
    "m" => 8,
    "s" => 9,
    "S" => 9,
    "A" => 9,
    "a" => 10,
    "b" => 10,
    "B" => 10,
    "z" => 11,
    "Z" => 11,
    "O" => 11,
    "v" => 11,
    "V" => 11,
    "X" => 11,
    "x" => 11
  }
  @unranked_field 12

  @prefer_cycle_24 ["H", "k"]
  # @prefer_cycle_12 ["h", "K"]

  # Inlining the `Application.app_dir/2` call at each compile-time use
  # site avoids leaving a `@time_preferences_path` module attribute
  # that a future maintainer could accidentally reference at runtime —
  # which would crash on any host that differs from the build host.
  # Issue #28.
  #
  # The data is embedded at compile time, so an ETF regeneration must
  # trigger recompilation of this module.
  @external_resource Application.app_dir(
                       :localize,
                       "priv/localize/supplemental_data/time_preferences.etf"
                     )

  @time_preferences (
                      path =
                        Application.app_dir(
                          :localize,
                          "priv/localize/supplemental_data/time_preferences.etf"
                        )

                      if File.exists?(path) do
                        path
                        |> File.read!()
                        |> :erlang.binary_to_term()
                      else
                        %{:"001" => %{preferred: "H", allowed: ["H", "h"]}}
                      end
                    )

  @spec best_match(atom() | String.t(), atom(), atom()) ::
          {:ok, atom()} | {:ok, {atom(), atom()}} | {:error, Exception.t()}
  def best_match(original_skeleton, locale_id, calendar_type \\ :gregorian) do
    skeleton =
      original_skeleton
      |> Kernel.to_string()
      |> replace_time_symbols(locale_id)

    with {:ok, skeleton_tokens} <- tokenize_skeleton(skeleton) do
      available_format_tokens = get_available_format_tokens(locale_id, calendar_type)

      skeleton_ordered = sort_tokens(skeleton_tokens)

      skeleton_keys =
        skeleton_ordered
        |> :proplists.get_keys()
        |> canonical_keys()

      candidates =
        available_format_tokens
        |> Enum.filter(&candidates_with_the_same_tokens(&1, skeleton_keys))
        |> Enum.map(&distance_from(&1, skeleton_ordered))
        |> Enum.sort_by(&rank/1)

      case candidates do
        [] ->
          try_date_and_time_skeletons(skeleton, original_skeleton, locale_id, calendar_type)

        [{format_id, _} | _rest] ->
          {:ok, format_id}
      end
    end
  end

  # # best_interval_match/3
  #
  # TR35 §Interval Formats step 2: where no `intervalFormatItem` matches the
  # requested skeleton exactly, take the closest one in the fallback chain,
  # "adjusting the string value field's width". The candidate set is the
  # locale's interval table rather than `availableFormats`, but the distance
  # rules are TR35's same ones, and `candidates_with_the_same_tokens/2` holds
  # the match to a width adjustment — a format carrying different fields can
  # never win, so a genuine miss still falls through to the fallback pattern.
  #
  # ### Arguments
  #
  # * `original_skeleton` is the requested skeleton.
  #
  # * `locale_id` is a resolved locale identifier.
  #
  # * `calendar_type` is a CLDR calendar name. The default is `:gregorian`.
  #
  # ### Returns
  #
  # * `{:ok, format_id}` naming an entry in the locale's interval table.
  #
  # * `:error` when no entry carries the same fields.
  #
  @spec best_interval_match(atom() | String.t(), atom(), atom()) :: {:ok, atom()} | :error
  def best_interval_match(original_skeleton, locale_id, calendar_type \\ :gregorian) do
    skeleton =
      original_skeleton
      |> Kernel.to_string()
      |> replace_time_symbols(locale_id)

    {:ok, skeleton_tokens} = tokenize_skeleton(skeleton)
    skeleton_ordered = sort_tokens(skeleton_tokens)

    skeleton_keys =
      skeleton_ordered
      |> :proplists.get_keys()
      |> canonical_keys()

    locale_id
    |> interval_format_tokens(calendar_type)
    |> Enum.filter(&candidates_with_the_same_tokens(&1, skeleton_keys))
    |> Enum.map(&distance_from(&1, skeleton_ordered))
    |> Enum.sort_by(&rank/1)
    |> case do
      [] -> :error
      [{format_id, _distance} | _rest] -> {:ok, format_id}
    end
  end

  # # subset_match/3
  #
  # Finds the closest available format whose fields are a strict subset of
  # the requested skeleton's, for TR35's append-item path: where no format
  # carries every field asked for, the nearest smaller one is augmented with
  # the fields it lacks.
  #
  # ### Arguments
  #
  # * `original_skeleton` is the requested skeleton.
  #
  # * `locale_id` is a resolved locale identifier.
  #
  # * `calendar_type` is a CLDR calendar name. The default is `:gregorian`.
  #
  # ### Returns
  #
  # * `{:ok, format_id, missing_tokens}` where `missing_tokens` are the
  #   requested `{symbol, count}` tuples the matched format does not carry.
  #
  # * `:error` when no format is a subset of the request.
  #
  @spec subset_match(atom() | String.t(), atom(), atom()) ::
          {:ok, atom(), [{String.t(), pos_integer()}]} | :error
  def subset_match(original_skeleton, locale_id, calendar_type \\ :gregorian) do
    skeleton =
      original_skeleton
      |> Kernel.to_string()
      |> replace_time_symbols(locale_id)

    with {:ok, skeleton_tokens} <- tokenize_skeleton(skeleton) do
      skeleton_ordered = sort_tokens(skeleton_tokens)
      skeleton_keys = skeleton_ordered |> :proplists.get_keys() |> canonical_keys()

      locale_id
      |> get_available_format_tokens(calendar_type)
      |> Enum.map(&subset_candidate(&1, skeleton_keys, skeleton_ordered))
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(fn {format_id, missing, distance, rank} ->
        {length(missing), distance, rank, Atom.to_string(format_id)}
      end)
      |> best_subset(skeleton_ordered)
    end
  end

  defp subset_candidate({format_id, tokens}, skeleton_keys, skeleton_ordered) do
    keys = tokens |> :proplists.get_keys() |> canonical_keys()
    missing = skeleton_keys -- keys

    # A strict subset: every field the format carries is asked for, and at
    # least one asked-for field is absent. An empty format matches nothing.
    if keys != [] and keys -- skeleton_keys == [] and missing != [] do
      # Rank on the fields the two have in common, so `:yMMMdQ` prefers
      # `yMMMd` over `yMMMMd` rather than falling to an alphabetical
      # tiebreak between two equally-sized subsets.
      shared =
        Enum.filter(skeleton_ordered, fn {symbol, _count} -> canonical_key(symbol) in keys end)

      {_id, distance} = distance_from({format_id, tokens}, shared)
      {format_id, missing, distance, field_rank(tokens)}
    end
  end

  defp best_subset([], _skeleton_ordered), do: :error

  defp best_subset([{format_id, missing_keys, _distance, _rank} | _rest], skeleton_ordered) do
    missing_tokens =
      Enum.filter(skeleton_ordered, fn {symbol, _count} ->
        canonical_key(symbol) in missing_keys
      end)

    {:ok, format_id, missing_tokens}
  end

  # # adjust_field_lengths/3
  #
  # Adjusts field lengths in a format pattern to match the requested
  # skeleton's field lengths.
  #
  # ### Arguments
  #
  # * `format` is a format pattern string or map of variants.
  #
  # * `skeleton_tokens` is a list of `{symbol, count}` tuples.
  #
  # * `matched_id` is the `availableFormats` id the pattern came from, or
  #   `nil`. TR35 leaves a pattern field alone where the *id's* field length
  #   already matches the request, so that locale data can override a
  #   requested width: `ru` answers the skeleton `yMd` with `dd.MM.y`, and
  #   narrowing that to `d.M.y` would discard the locale's own choice.
  #
  # ### Returns
  #
  # * `{:ok, adjusted_format}`.
  #
  @spec adjust_field_lengths(
          String.t() | map(),
          [{String.t(), non_neg_integer()}],
          atom() | String.t() | nil
        ) :: {:ok, String.t() | map()}
  def adjust_field_lengths(format, skeleton_tokens, matched_id \\ nil)

  def adjust_field_lengths(format, skeleton_tokens, matched_id) when is_map(format) do
    revised =
      Enum.map(format, fn
        {style, pattern} when is_binary(pattern) ->
          {:ok, adjusted} = adjust_field_lengths(pattern, skeleton_tokens, matched_id)
          {style, adjusted}

        other ->
          other
      end)
      |> Map.new()

    {:ok, revised}
  end

  def adjust_field_lengths(format, skeleton_tokens, matched_id) when is_binary(format) do
    id_tokens = id_tokens(matched_id)

    adjusted =
      format
      |> tokenize_format_string()
      |> Enum.reduce([], &adjust_field_length(&1, &2, skeleton_tokens, id_tokens))
      |> Enum.reverse()
      |> List.flatten()
      |> List.to_string()
      |> strip_day_periods_for_capital_j(skeleton_tokens)

    {:ok, adjusted}
  end

  # TR35's `J` asks for the locale's preferred hour "but, unlike 'j', it
  # requests no dayPeriod marker", so its pattern drops the day period and
  # the space that set it apart: "h:mm a" becomes "h:mm" and ja's "aK:mm"
  # becomes "K:mm". Quoted text is left alone.
  defp strip_day_periods_for_capital_j(pattern, skeleton_tokens) do
    if :proplists.is_defined("J", skeleton_tokens) do
      pattern
      |> String.split("'")
      |> Enum.with_index()
      |> Enum.map_join("'", fn
        {piece, index} when rem(index, 2) == 0 -> strip_day_period(piece)
        {piece, _index} -> piece
      end)
    else
      pattern
    end
  end

  defp strip_day_period(piece) do
    Regex.replace(~r/(\s*)[abB]+(\s*)/u, piece, fn _match, before, after_period ->
      if before != "" and after_period != "", do: before, else: ""
    end)
  end

  defp id_tokens(nil), do: []

  defp id_tokens(matched_id) do
    {:ok, tokens} = tokenize_skeleton(Kernel.to_string(matched_id))
    tokens
  end

  # TR35: "When the pattern field corresponds to an availableFormats skeleton
  # with a field length that matches the field length in the requested
  # skeleton, the pattern field length should not be adjusted. This permits
  # locale data to override a requested field length." `ru` answers the
  # skeleton `yMd` with `dd.MM.y`; narrowing that to `d.M.y` would discard
  # the locale's own choice. The rule is about width, so it does not apply to
  # the clauses that substitute one symbol for another.
  defp locale_states_width?(id_tokens, symbol, skeleton_tokens) do
    case :proplists.get_value(symbol, id_tokens, nil) do
      nil -> false
      id_count -> id_count == :proplists.get_value(symbol, skeleton_tokens, nil)
    end
  end

  # # split_fractional_seconds/1
  #
  # Splits the fractional-second field (S) out of a requested
  # skeleton, per TR35 skeleton matching: fractional seconds do not
  # participate in matching (no CLDR format contains them); they are
  # appended to the matched pattern's seconds field afterwards.
  #
  # Returns `{skeleton_without_s_field, fraction_digit_count}`. The
  # count is 0 — and the skeleton unchanged — when the skeleton has
  # no S field or no s field to attach the fraction to.
  @spec split_fractional_seconds(atom() | String.t()) ::
          {atom() | String.t(), non_neg_integer()}
  def split_fractional_seconds(skeleton) do
    skeleton_string = Kernel.to_string(skeleton)

    with [s_run] <- Regex.run(~r/S+/, skeleton_string),
         true <- String.contains?(skeleton_string, "s") do
      stripped = String.replace(skeleton_string, ~r/S+/, "")
      {interned_or_string(stripped), String.length(s_run)}
    else
      _no_fraction_or_no_seconds -> {skeleton_or_string(skeleton), 0}
    end
  end

  # The skeleton comes from the caller and the stripped form is derived from
  # it, so neither is interned here. Every `availableFormats` key is an atom
  # created when the locale data loads, so a form that is not already an atom
  # cannot name a format; handing the matcher the string lets it take its
  # ordinary best-match path rather than growing the atom table.
  defp skeleton_or_string(skeleton) when is_atom(skeleton), do: skeleton
  defp skeleton_or_string(skeleton) when is_binary(skeleton), do: interned_or_string(skeleton)

  defp interned_or_string(string) do
    Localize.Utils.Helpers.existing_atom(string) || string
  end

  # # append_fractional_seconds/3
  #
  # Appends `count` fractional-second symbols (S) directly after the
  # last unquoted seconds field (s) of a format pattern. The format
  # compiler inserts the decimal-separator token between adjacent
  # `s` and `S` fields, so no literal separator is added here.
  #
  # A count of 0, a pattern without an unquoted seconds field, or a
  # non-binary pattern passes through unchanged.
  @spec append_fractional_seconds(term(), non_neg_integer(), atom()) :: term()
  def append_fractional_seconds(pattern, 0, _locale_id), do: pattern

  def append_fractional_seconds(pattern, count, _locale_id) when is_binary(pattern) do
    case last_unquoted_seconds_index(pattern) do
      nil ->
        pattern

      index ->
        {prefix, suffix} = String.split_at(pattern, index + 1)
        prefix <> String.duplicate("S", count) <> suffix
    end
  end

  def append_fractional_seconds(pattern, _count, _locale_id), do: pattern

  # Index (in graphemes) of the last "s" outside single-quoted
  # literal text. A doubled apostrophe toggles the quote state twice,
  # so it does not affect the outcome.
  defp last_unquoted_seconds_index(pattern) do
    pattern
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.reduce({false, nil}, fn
      {"'", _index}, {in_quote, last} -> {not in_quote, last}
      {"s", index}, {false, _last} -> {false, index}
      {_grapheme, _index}, state -> state
    end)
    |> elem(1)
  end

  # ── Token helpers ──────────────────────────────────────────

  @zone_symbols ["z", "Z", "v", "V", "O", "X", "x"]

  @doc """
  Returns true when a skeleton names only time zone fields.

  Such a skeleton needs no field ordering — there is only one field — so it
  is its own pattern, and looking it up in `availableFormats` (which carries
  no zone-only entries) or running it through the matcher only fails.

  ### Arguments

  * `skeleton` is a skeleton atom or string.

  ### Returns

  * `true` or `false`.

  ### Examples

      iex> Localize.DateTime.Format.Match.zone_only_skeleton?(:vvvv)
      true

      iex> Localize.DateTime.Format.Match.zone_only_skeleton?(:yMMMd)
      false

  """
  @spec zone_only_skeleton?(String.t() | atom()) :: boolean()
  def zone_only_skeleton?(skeleton) do
    {:ok, tokens} = tokenize_skeleton(skeleton)

    tokens != [] and Enum.all?(tokens, fn {symbol, _count} -> symbol in @zone_symbols end)
  end

  @doc false
  @spec tokenize_skeleton(String.t() | atom()) :: {:ok, [{String.t(), pos_integer()}]}
  def tokenize_skeleton(skeleton) when is_atom(skeleton) do
    skeleton |> Atom.to_string() |> tokenize_skeleton()
  end

  def tokenize_skeleton(skeleton) when is_binary(skeleton) do
    skeleton
    |> String.graphemes()
    |> Enum.chunk_by(& &1)
    |> Enum.map(fn chars -> {hd(chars), length(chars)} end)
    |> then(&{:ok, &1})
  end

  # A pattern's fields are runs of one letter, but text in single quotes is
  # literal and passes through untouched: dsb's `jjm` pattern is
  # "'zeg'. H:mm", and reading its quoted `z` as a zone field deleted it.
  defp tokenize_format_string(string) do
    string
    |> String.graphemes()
    |> tokenize_format([])
  end

  defp tokenize_format([], tokens), do: Enum.reverse(tokens)

  defp tokenize_format(["'" | rest], tokens) do
    {quoted, rest} = take_quoted(rest, ["'"])
    tokenize_format(rest, [{:literal, quoted} | tokens])
  end

  defp tokenize_format([char | _rest] = graphemes, tokens) do
    {run, rest} = Enum.split_while(graphemes, &(&1 == char))
    tokenize_format(rest, [run | tokens])
  end

  # A doubled quote inside quoted text is an escaped quote. An unterminated
  # quote runs to the end of the pattern.
  defp take_quoted(["'", "'" | rest], taken), do: take_quoted(rest, ["'", "'" | taken])
  defp take_quoted(["'" | rest], taken), do: {Enum.join(Enum.reverse(["'" | taken])), rest}
  defp take_quoted([char | rest], taken), do: take_quoted(rest, [char | taken])
  defp take_quoted([], taken), do: {Enum.join(Enum.reverse(taken)), []}

  defp get_available_format_tokens(locale_id, calendar_type) do
    case Format.available_formats(locale_id, calendar_type) do
      {:ok, formats} ->
        formats
        |> Map.keys()
        |> Enum.map(fn format_id ->
          {:ok, tokens} = tokenize_skeleton(Atom.to_string(format_id))
          {format_id, match_tokens(tokens)}
        end)

      _ ->
        []
    end
  end

  # The interval table is keyed by skeleton, with two siblings that are not
  # skeletons: the fallback pattern and the range separator patterns.
  @non_skeleton_interval_keys [:interval_format_fallback, :interval_format_ranges]

  defp interval_format_tokens(locale_id, calendar_type) do
    case Format.interval_formats(locale_id, calendar_type) do
      {:ok, formats} ->
        formats
        |> Map.keys()
        |> Enum.reject(&(&1 in @non_skeleton_interval_keys))
        |> Enum.map(fn format_id ->
          {:ok, tokens} = tokenize_skeleton(Atom.to_string(format_id))
          {format_id, match_tokens(tokens)}
        end)

      _no_interval_formats ->
        []
    end
  end

  def sort_tokens(tokens) do
    tokens
    |> match_tokens()
    |> Enum.sort(fn {symbol_a, _}, {symbol_b, _} ->
      canonical_key(symbol_a) < canonical_key(symbol_b)
    end)
  end

  # The tokens a skeleton or an `availableFormats` id is matched on. CLDR
  # writes a 12-hour format's id without its day period (`en`'s `h` is
  # "h a"), so an `h` or `K` with no day period carries an implied `a`, and a
  # request for `ha` finds "h a" where it found `Bh`'s "h B". An `H` or `k`
  # drops any day period a skeleton asks for: TR35 lets a 24-hour hour match
  # only a 24-hour format, and ICU's pattern generator renders `Ha` as "HH".
  # Applying this twice changes nothing.
  defp match_tokens(tokens) do
    cond do
      Enum.any?(tokens, fn {symbol, _count} -> symbol in @hour_24 end) ->
        Enum.reject(tokens, fn {symbol, _count} -> symbol in @day_period end)

      Enum.any?(tokens, fn {symbol, _count} -> symbol in @hour_12 end) and
          not Enum.any?(tokens, fn {symbol, _count} -> symbol in @day_period end) ->
        [{"a", 1} | tokens]

      true ->
        tokens
    end
  end

  # ── Candidate filtering ────────────────────────────────────

  defp candidates_with_the_same_tokens({_format_id, tokens}, skeleton_keys)
       when length(tokens) == length(skeleton_keys) do
    token_keys =
      tokens
      |> :proplists.get_keys()
      |> canonical_keys()

    token_keys == skeleton_keys
  end

  defp candidates_with_the_same_tokens(_format_tokens, _skeleton_keys), do: false

  # ── Distance calculation ────────────────────────────────────

  # UTS #35 skeleton distance: guard clauses per symbol-class and
  # numeric/alpha width-class combination. The candidate tokens are
  # in pattern-string order; the skeleton is canonically sorted, so
  # the candidate must be sorted the same way or the zip compares
  # unrelated fields.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp distance_from({token_id, tokens}, skeleton) do
    distance =
      Enum.zip_reduce(sort_tokens(tokens), skeleton, 0, fn
        # Same symbol, both numeric or both text
        {symbol, count_a}, {symbol, count_b}, distance ->
          if text_field?(symbol, count_a) == text_field?(symbol, count_b),
            do: distance + width_distance(symbol, count_a, symbol, count_b),
            else: distance + 10

        # a, b and B are one field to TR35, but ICU's pattern generator keeps b
        # nearer a than B, so `hb` takes `h a` (rendered "h b") over `Bh`.
        {sym_a, count_a}, {sym_b, count_b}, distance
        when sym_a in @day_period and sym_b in @day_period ->
          pair = Enum.sort([sym_a, sym_b])

          distance + width_distance(sym_a, count_a, sym_b, count_b) +
            Map.fetch!(%{["a", "b"] => 10, ["B", "b"] => 15, ["B", "a"] => 20}, pair)

        # Different compatible symbols. TR35 lets an h or K skeleton field
        # match only a 12-hour field (h or K), and an H or k only a 24-hour
        # one, so an hour of the other cycle is not compatible.
        {sym_a, count_a}, {sym_b, count_b}, distance
        when (sym_a in @year and sym_b in @year) or
               (sym_a in @month and sym_b in @month) or
               (sym_a in @quarter and sym_b in @quarter) or
               (sym_a in @day_of_week and sym_b in @day_of_week) or
               (sym_a in @hour_12 and sym_b in @hour_12) or
               (sym_a in @hour_24 and sym_b in @hour_24) or
               (sym_a in @time_zone and sym_b in @time_zone) ->
          if text_field?(sym_a, count_a) == text_field?(sym_b, count_b),
            do: distance + width_distance(sym_a, count_a, sym_b, count_b) + 10,
            else: distance + abs(count_a - count_b) + 20

        _other_a, _other_b, distance ->
          distance + 30
      end)

    {token_id, distance}
  end

  # A field is text at three letters or more, and at every width for the
  # symbols with no numeric form: `E` is the abbreviated weekday at one to
  # three letters, where `e` and `c` are the weekday's number.
  defp text_field?(symbol, count), do: symbol in @always_alpha or count > 2

  # Numeric widths differ by digit count. Text widths do not run in letter
  # order: CLDR's reference pattern generator places narrow (five letters)
  # beside short (six), short beside abbreviated (three), and abbreviated
  # beside wide (four), so a narrow request prefers an abbreviated format to
  # a wide one. `ja` answers `EEEEEd` from `Ed`'s "d日(E)", not `EEEEd`'s
  # "d日EEEE".
  defp width_distance(sym_a, count_a, sym_b, count_b) do
    if text_field?(sym_a, count_a) and text_field?(sym_b, count_b),
      do: abs(text_width_rank(count_a) - text_width_rank(count_b)),
      else: abs(count_a - count_b)
  end

  defp text_width_rank(count) when count <= 3, do: 3
  defp text_width_rank(4), do: 4
  defp text_width_rank(5), do: 1
  defp text_width_rank(6), do: 2
  defp text_width_rank(count), do: count

  # TR35 §Missing Skeleton Fields: formats that lack a requested field and
  # are otherwise equally close are ranked "by their matching fields in the
  # order listed in step 1", so `en`'s `EEEEMMMM` builds on its month format
  # and appends the weekday rather than building on `E` and appending the
  # month.
  defp field_rank(tokens) do
    tokens
    |> Enum.map(fn {symbol, _count} -> Map.get(@field_ranks, symbol, @unranked_field) end)
    |> Enum.sort()
  end

  # Two formats can sit at the same distance from a skeleton: `ja` answers
  # `yMMMMEEEEd` with `yMMMEEEEd` and `yMMMMEd` equally well, each one alpha
  # width away. Ordering by distance alone left the winner to the iteration
  # order of the available-formats map, and Erlang hashes atom keys by their
  # internal reference — so the order depended on when those atoms were
  # created in the VM, and the same skeleton could resolve to a different
  # pattern from one run to the next. The format id breaks the tie the same
  # way `subset_match/3` breaks its own.
  defp rank({format_id, distance}), do: {distance, Atom.to_string(format_id)}

  # ── Canonical key mapping ───────────────────────────────────

  defp canonical_keys(keys) do
    keys
    |> Enum.map(&canonical_key/1)
    |> Enum.sort()
  end

  defp canonical_key(key) do
    cond do
      key in @year -> "y"
      key in @month -> "M"
      key in @quarter -> "Q"
      key in @day_of_week -> "E"
      key in @day_period -> "a"
      key in @hour -> "H"
      key in @time_zone -> "v"
      true -> key
    end
  end

  # ── Split date/time skeletons ───────────────────────────────

  defp try_date_and_time_skeletons(skeleton, original, locale_id, calendar_type) do
    with {date_skeleton, time_skeleton} <- separate_date_and_time_fields(skeleton),
         {:ok, date_format} <- best_match(date_skeleton, locale_id, calendar_type),
         {:ok, time_format} <- best_match(time_skeleton, locale_id, calendar_type) do
      {:ok, {date_format, time_format}}
    else
      _ ->
        {:error,
         Localize.DateTimeUnresolvedFormatError.exception(
           format: original,
           locale: locale_id
         )}
    end
  end

  # # separate_date_and_time/1
  #
  # Splits a skeleton into its date and time halves, or returns `nil` when
  # it is wholly one or the other.
  #
  @spec separate_date_and_time(atom() | String.t()) :: {String.t(), String.t()} | nil
  def separate_date_and_time(skeleton) do
    skeleton
    |> Kernel.to_string()
    |> separate_date_and_time_fields()
  end

  # A character that is neither a date nor a time symbol makes the skeleton
  # unsplittable rather than being dropped, so `:bogus` does not resolve as
  # the date "gu" and the time "bs".
  defp separate_date_and_time_fields(skeleton) do
    {date_fields, time_fields, unknown} =
      skeleton
      |> String.graphemes()
      |> Enum.reduce({[], [], []}, fn char, {date_fields, time_fields, unknown} ->
        cond do
          char in @date_symbols -> {[char | date_fields], time_fields, unknown}
          char in @time_symbols -> {date_fields, [char | time_fields], unknown}
          true -> {date_fields, time_fields, [char | unknown]}
        end
      end)

    if date_fields != [] and time_fields != [] and unknown == [] do
      {date_fields |> Enum.reverse() |> List.to_string(),
       time_fields |> Enum.reverse() |> List.to_string()}
    else
      nil
    end
  end

  # ── Field length adjustment ─────────────────────────────────

  # The fields spelled by more than one symbol: month, quarter and weekday.
  @related_symbol_fields @month ++ @quarter ++ @day_of_week
  # TR35's zone symbols stand in for one another, the ISO 8601 `X` and `x`
  # as well as the named forms: `jmX` matched to `hmv` renders `h:mm a X`.
  @substitutable_zone_fields ["v", "V", "O", "z", "Z", "X", "x"]
  @hms_fields ["H", "h", "K", "k", "m", "s", "S"]

  defp adjust_field_length({:literal, text}, acc, _skeleton_tokens, _id_tokens) do
    [text | acc]
  end

  defp adjust_field_length([char | _rest] = field, acc, skeleton_tokens, id_tokens)
       when char in @related_symbol_fields do
    # The requested token may be spelled with either form of the field —
    # `L` and `M` are both months, `E`, `e` and `c` all weekdays — so the
    # lookup canonicalises the skeleton's keys as well as the format's.
    # Without it a requested `LLLL` never found the `MMM` format's month, and
    # `en`'s `EEEE` never found the "ccc" of its `E` format. The pattern keeps
    # its own symbol: the locale chose the stand-alone or format form.
    canonical = canonical_key(char)

    requested =
      Enum.find(skeleton_tokens, fn {key, _count} -> canonical_key(key) == canonical end)

    stated = Enum.find(id_tokens, fn {key, _count} -> canonical_key(key) == canonical end)

    case requested do
      nil ->
        [field | acc]

      # TR35 rule 2: the format's own skeleton already asks for this width,
      # so the pattern's width is the locale's answer to it.
      {symbol, count} when stated != nil ->
        if same_width?(stated, {symbol, count}),
          do: [field | acc],
          else: [adjusted_field(field, symbol, count) | acc]

      {symbol, count} ->
        [adjusted_field(field, symbol, count) | acc]
    end
  end

  # The zone the skeleton asks for replaces the pattern's, keeping the
  # pattern's width where the matched id already asks for the requested one
  # (TR35 rule 2): el's `Hmsv` is "HH:mm:ss (vvvv)", so `Hmsv` keeps its
  # long generic name. With no zone asked for, the pattern's zone stands.
  defp adjust_field_length([char | _rest] = field, acc, skeleton_tokens, id_tokens)
       when char in @substitutable_zone_fields do
    stated = Enum.find(id_tokens, fn {key, _count} -> key in @substitutable_zone_fields end)

    case find_substitutable_field(@substitutable_zone_fields, skeleton_tokens) do
      {"", 0} ->
        [field | acc]

      {symbol, count} ->
        width = if match?({_key, ^count}, stated), do: length(field), else: count
        [List.duplicate(symbol, width) | acc]
    end
  end

  # TR35 matches a, b and B as one field. A `b` or `B` in the skeleton asks
  # for that style of day period, so it replaces the pattern's: `hb` matched
  # to `h a` renders `h b`. An `a` beside an hour is optional — TR35 treats
  # `ha` as `h` — so the locale's own day period stands at the width asked
  # for, and zh-Hant's `ha` is its "Bh時". With none asked for, it stands at
  # the width a `j` or `C` asks for.
  defp adjust_field_length([char | _rest] = field, acc, skeleton_tokens, _id_tokens)
       when char in @day_period do
    case Enum.find(skeleton_tokens, fn {symbol, _count} -> symbol in @day_period end) do
      {"a", count} when count > 3 -> [List.duplicate(char, count) | acc]
      {"a", _abbreviated} -> [field | acc]
      {symbol, count} -> [List.duplicate(symbol, count) | acc]
      nil -> [input_hour_day_period(field, skeleton_tokens) | acc]
    end
  end

  defp adjust_field_length([char | _rest] = field, acc, _skeleton_tokens, _id_tokens)
       when char in @hms_fields do
    [field | acc]
  end

  # A year asked for as `Y`, `u` or `r` counts differently from the
  # pattern's `y`, so the requested symbol replaces it; `YMd` matched to
  # `yMd` renders "M/d/Y". A `y` request keeps the symbol the locale wrote,
  # as en's "'week' w 'of' Y" for `yw` does, and a `U` in a calendar without
  # cyclic years is its numeric year, so the pattern's year stands.
  defp adjust_field_length([char | _rest] = field, acc, skeleton_tokens, id_tokens)
       when char in @year do
    stated = Enum.find(id_tokens, fn {key, _count} -> key in @year end)

    case Enum.find(skeleton_tokens, fn {key, _count} -> key in @year end) do
      {"U", _count} ->
        [field | acc]

      {symbol, count} ->
        output_symbol = if symbol == "y", do: char, else: symbol
        # TR35 rule 2, as for every other field.
        width = if match?({_key, ^count}, stated), do: length(field), else: count
        [List.duplicate(output_symbol, width) | acc]

      nil ->
        [field | acc]
    end
  end

  defp adjust_field_length([char | _rest] = field, acc, skeleton_tokens, id_tokens) do
    field_length = length(field)

    requested_length =
      if locale_states_width?(id_tokens, char, skeleton_tokens),
        do: field_length,
        else: :proplists.get_value(char, skeleton_tokens, field_length)

    if field_length == requested_length do
      [field | acc]
    else
      [List.duplicate(char, requested_length) | acc]
    end
  end

  # TR35 rule 1: a width moves only within its class, never between numeric
  # and text. A text width carries the form it names, so a pattern's "ccc"
  # asked for as `EEEE` becomes "cccc", and asked for as `E` stays "ccc".
  defp adjusted_field([char | _rest] = field, symbol, count) do
    pattern_count = length(field)

    cond do
      text_field?(char, pattern_count) != text_field?(symbol, count) -> field
      effective_width(char, pattern_count) == effective_width(symbol, count) -> field
      true -> List.duplicate(char, effective_width(symbol, count))
    end
  end

  # TR35's input hour symbols carry a day-period width in their length: one
  # or two letters of `j` or `C` ask for the abbreviated day period, three
  # or four the wide one, five or six the narrow one. The width applies to
  # the day period the pattern already uses, whichever symbol that is, so
  # zh-Hant's `jjj` renders its "Bh時" as "BBBBh時".
  defp input_hour_day_period([char | _rest] = field, skeleton_tokens) do
    case Enum.find(skeleton_tokens, fn {symbol, _count} -> symbol in ["j", "C"] end) do
      {_symbol, count} when count >= 5 -> List.duplicate(char, 5)
      {_symbol, count} when count >= 3 -> List.duplicate(char, 4)
      _abbreviated_or_none -> field
    end
  end

  defp same_width?({symbol_a, count_a}, {symbol_b, count_b}) do
    effective_width(symbol_a, count_a) == effective_width(symbol_b, count_b)
  end

  # One to three letters of `E` are all the abbreviated weekday, the width
  # `ccc` and `eee` spell with three.
  defp effective_width(symbol, count) when symbol in @always_alpha, do: max(count, 3)
  defp effective_width(_symbol, count), do: count

  defp find_substitutable_field(fields, skeleton) do
    Enum.reduce_while(fields, {"", 0}, fn field, acc ->
      if count = :proplists.get_value(field, skeleton, nil) do
        {:halt, {field, count}}
      else
        {:cont, acc}
      end
    end)
  end

  # ── Time symbol replacement ──────────────────────────────

  # Replaces the meta-symbols "j", "J", and "C" in skeletons
  # with the locale-preferred hour format symbol.
  #
  # "j" → preferred hour symbol (h, H, K, or k)
  # "J" → preferred hour symbol without day period (no AM/PM)
  # "C" → first allowed hour symbol

  defp replace_time_symbols(skeleton, locale_id) do
    if String.contains?(skeleton, ["j", "J", "C"]) do
      prefs = time_preferences_for(locale_id)
      preferred = prefs.preferred
      do_replace_time_symbols(skeleton, preferred, allowed_hour(prefs, skeleton))
    else
      skeleton
    end
  end

  # `C` takes the first allowed hour format with its day period ("hB"),
  # unless the skeleton asks for a day period itself: ICU's pattern
  # generator renders zh-Hant's `Ca` as "ah時", not with two day periods.
  defp allowed_hour(prefs, skeleton) do
    allowed = hd(prefs.allowed)

    if String.contains?(skeleton, @day_period),
      do: String.replace(allowed, @day_period, ""),
      else: allowed
  end

  @doc false
  # Applies the same hour-symbol substitution as the `j`/`J`/`C`
  # meta-symbol resolution, but driven by an externally-supplied
  # preferred hour symbol (one of `"h"`, `"H"`, `"K"`, `"k"`) and only
  # to the meta-symbols in `symbols`. Used by `Localize.Time` to honour
  # a locale's `-u-hc-` Unicode-extension override on user-supplied
  # skeleton atoms; a meta-symbol it leaves is resolved from the
  # locale's own hour data when the skeleton is matched.
  def apply_hc_substitution(skeleton, preferred, symbols)
      when is_binary(skeleton) and is_binary(preferred) and is_list(symbols) do
    kept = ["j", "J", "C"] -- symbols

    skeleton
    |> String.graphemes()
    |> Enum.chunk_by(&(&1 in kept))
    |> Enum.map_join(fn [first | _rest] = chunk ->
      piece = Enum.join(chunk)
      if first in kept, do: piece, else: do_replace_time_symbols(piece, preferred, preferred)
    end)
  end

  defp do_replace_time_symbols("", _preferred, _allowed), do: ""

  defp do_replace_time_symbols(<<"j", rest::binary>>, preferred, allowed) do
    preferred <> do_replace_time_symbols(rest, preferred, allowed)
  end

  defp do_replace_time_symbols(<<"J", rest::binary>>, preferred, allowed) do
    clean = String.replace(preferred, ~r/[abB]/, "")
    clean <> do_replace_time_symbols(rest, preferred, allowed)
  end

  defp do_replace_time_symbols(<<"C", rest::binary>>, preferred, allowed) do
    allowed <> do_replace_time_symbols(rest, preferred, allowed)
  end

  # Remove day period symbols (a, b, B) when using 24-hour cycle
  defp do_replace_time_symbols(<<code::binary-1, rest::binary>>, preferred, allowed)
       when code in @day_period and preferred in @prefer_cycle_24 do
    do_replace_time_symbols(rest, preferred, allowed)
  end

  # Replace 12-hour with 24-hour when locale prefers 24-hour
  defp do_replace_time_symbols(<<"h", rest::binary>>, "H" = preferred, allowed) do
    preferred <> do_replace_time_symbols(rest, preferred, allowed)
  end

  defp do_replace_time_symbols(<<"K", rest::binary>>, "H" = preferred, allowed) do
    preferred <> do_replace_time_symbols(rest, preferred, allowed)
  end

  defp do_replace_time_symbols(<<"h", rest::binary>>, "k" = preferred, allowed) do
    preferred <> do_replace_time_symbols(rest, preferred, allowed)
  end

  defp do_replace_time_symbols(<<"K", rest::binary>>, "k" = preferred, allowed) do
    preferred <> do_replace_time_symbols(rest, preferred, allowed)
  end

  # Replace 24-hour with 12-hour when locale prefers 12-hour
  defp do_replace_time_symbols(<<"H", rest::binary>>, <<"h", _::binary>> = preferred, allowed) do
    preferred <> do_replace_time_symbols(rest, preferred, allowed)
  end

  defp do_replace_time_symbols(<<"k", rest::binary>>, <<"h", _::binary>> = preferred, allowed) do
    preferred <> do_replace_time_symbols(rest, preferred, allowed)
  end

  defp do_replace_time_symbols(<<"H", rest::binary>>, <<"K", _::binary>> = preferred, allowed) do
    preferred <> do_replace_time_symbols(rest, preferred, allowed)
  end

  defp do_replace_time_symbols(<<"k", rest::binary>>, <<"K", _::binary>> = preferred, allowed) do
    preferred <> do_replace_time_symbols(rest, preferred, allowed)
  end

  # Pass through all other characters
  defp do_replace_time_symbols(<<char::binary-1, rest::binary>>, preferred, allowed) do
    char <> do_replace_time_symbols(rest, preferred, allowed)
  end

  @doc false
  # Locale -> territory -> root (:"001") fallback chain over the CLDR
  # time-preference data, with atom/binary input normalisation.
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def time_preferences_for(locale_id) do
    # `@time_preferences` keys are pre-atomised at compile time (CLDR
    # locale ids and territory codes), so `existing_atom/1` resolves
    # any known locale and returns nil for everything else. Unknown
    # binaries no longer grow the atom table.
    locale_atom =
      cond do
        is_atom(locale_id) -> locale_id
        is_binary(locale_id) -> Localize.Utils.Helpers.existing_atom(locale_id)
        true -> nil
      end

    # Look up by locale name first, then by language and territory, then by
    # territory. TR35 §Time Data lets `regions` name a locale as well as a
    # region (`hi_IN` allows "hB h H" where `IN` allows "h H"), and CLDR's
    # JSON keys those entries by the hyphenated locale, "hi-IN".
    {language, territory} =
      with true <- not is_nil(locale_atom),
           {:ok, %{language: language, territory: territory}} when not is_nil(territory) <-
             Localize.validate_locale(locale_atom) do
        {language, territory}
      else
        _no_territory -> {nil, nil}
      end

    Map.get(@time_preferences, locale_atom) ||
      (territory && Map.get(@time_preferences, "#{language}-#{territory}")) ||
      (territory && Map.get(@time_preferences, territory)) ||
      Map.fetch!(@time_preferences, :"001")
  end
end
