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
  @time_symbols ~w(h H k K m s S v V z Z x X O a b B)

  @hour ["k", "h", "K", "H"]
  @day_period ["a", "b", "B"]
  @month ["L", "M"]
  @day_of_week ["c", "E"]
  @time_zone ["x", "X", "v", "V", "z", "Z", "O"]

  @prefer_cycle_24 ["H", "k"]
  # @prefer_cycle_12 ["h", "K"]

  @time_preferences_path Path.join(
                           :code.priv_dir(:localize) |> Kernel.to_string(),
                           "cldr/supplemental_data/time_preferences.etf"
                         )

  @time_preferences (if File.exists?(@time_preferences_path) do
                       @time_preferences_path
                       |> File.read!()
                       |> :erlang.binary_to_term()
                     else
                       %{:"001" => %{preferred: "H", allowed: ["H", "h"]}}
                     end)

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
        |> Enum.sort(&compare_counts/2)

      case candidates do
        [] ->
          try_date_and_time_skeletons(skeleton, original_skeleton, locale_id, calendar_type)

        [{format_id, _} | _rest] ->
          {:ok, format_id}
      end
    end
  end

  # # adjust_field_lengths/2
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
  # ### Returns
  #
  # * `{:ok, adjusted_format}`.
  #
  @spec adjust_field_lengths(String.t() | map(), [{String.t(), non_neg_integer()}]) ::
          {:ok, String.t() | map()}
  def adjust_field_lengths(format, skeleton_tokens) when is_map(format) do
    revised =
      Enum.map(format, fn
        {style, pattern} when is_binary(pattern) ->
          {:ok, adjusted} = adjust_field_lengths(pattern, skeleton_tokens)
          {style, adjusted}

        other ->
          other
      end)
      |> Map.new()

    {:ok, revised}
  end

  def adjust_field_lengths(format, skeleton_tokens) when is_binary(format) do
    format_tokens = tokenize_format_string(format)

    adjusted =
      Enum.reduce(format_tokens, [], &adjust_field_length(&1, &2, skeleton_tokens))
      |> Enum.reverse()
      |> List.flatten()
      |> List.to_string()

    {:ok, adjusted}
  end

  # ── Token helpers ──────────────────────────────────────────

  defp tokenize_skeleton(skeleton) when is_binary(skeleton) do
    skeleton
    |> String.graphemes()
    |> Enum.chunk_by(& &1)
    |> Enum.map(fn chars -> {hd(chars), length(chars)} end)
    |> then(&{:ok, &1})
  end

  defp tokenize_format_string(string) do
    string
    |> String.graphemes()
    |> Enum.chunk_by(& &1)
  end

  defp get_available_format_tokens(locale_id, calendar_type) do
    case Format.available_formats(locale_id, calendar_type) do
      {:ok, formats} ->
        formats
        |> Map.keys()
        |> Enum.map(fn format_id ->
          {:ok, tokens} = tokenize_skeleton(Atom.to_string(format_id))
          {format_id, tokens}
        end)

      _ ->
        []
    end
  end

  def sort_tokens(tokens) do
    Enum.sort(tokens, fn {symbol_a, _}, {symbol_b, _} ->
      canonical_key(symbol_a) < canonical_key(symbol_b)
    end)
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

  defp distance_from({token_id, tokens}, skeleton) do
    distance =
      Enum.zip_reduce(tokens, skeleton, 0, fn
        # Same symbol, both numeric or both alpha
        {symbol, count_a}, {symbol, count_b}, distance
        when (count_a in [1, 2] and count_b in [1, 2]) or
               (count_a > 2 and count_b > 2) ->
          distance + abs(count_a - count_b)

        # Same symbol, different type (numeric vs alpha)
        {symbol, _count_a}, {symbol, _count_b}, distance ->
          distance + 10

        # Different compatible symbols, same type
        {sym_a, count_a}, {sym_b, count_b}, distance
        when ((sym_a in @month and sym_b in @month) or
                (sym_a in @day_of_week and sym_b in @day_of_week) or
                (sym_a in @day_period and sym_b in @day_period) or
                (sym_a in @hour and sym_b in @hour) or
                (sym_a in @time_zone and sym_b in @time_zone)) and
               ((count_a in [1, 2] and count_b in [1, 2]) or
                  (count_a > 2 and count_b > 2)) ->
          distance + abs(count_a - count_b) + 10

        # Different compatible symbols, different type
        {sym_a, count_a}, {sym_b, count_b}, distance
        when (sym_a in @month and sym_b in @month) or
               (sym_a in @day_of_week and sym_b in @day_of_week) or
               (sym_a in @day_period and sym_b in @day_period) or
               (sym_a in @hour and sym_b in @hour) or
               (sym_a in @time_zone and sym_b in @time_zone) ->
          distance + abs(count_a - count_b) + 20

        _other_a, _other_b, distance ->
          distance + 30
      end)

    {token_id, distance}
  end

  defp compare_counts({_, count_a}, {_, count_b}), do: count_a < count_b

  # ── Canonical key mapping ───────────────────────────────────

  defp canonical_keys(keys) do
    keys
    |> Enum.map(&canonical_key/1)
    |> Enum.sort()
  end

  defp canonical_key(key) do
    cond do
      key in @month -> "M"
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

  defp separate_date_and_time_fields(skeleton) do
    {date_fields, time_fields} =
      skeleton
      |> String.graphemes()
      |> Enum.reduce({[], []}, fn char, {date_fields, time_fields} ->
        date_fields = if char in @date_symbols, do: [char | date_fields], else: date_fields
        time_fields = if char in @time_symbols, do: [char | time_fields], else: time_fields
        {date_fields, time_fields}
      end)

    if length(date_fields) > 0 and length(time_fields) > 0 do
      {date_fields |> Enum.reverse() |> List.to_string(),
       time_fields |> Enum.reverse() |> List.to_string()}
    else
      nil
    end
  end

  # ── Field length adjustment ─────────────────────────────────

  @numeric_and_alpha_fields ["M", "L", "e", "q", "Q"]
  @substitutable_zone_fields ["v", "V", "O", "z", "Z"]
  @hms_fields ["H", "h", "K", "k", "m", "s", "S"]

  defp adjust_field_length([char | _rest] = field, acc, skeleton_tokens)
       when char in @numeric_and_alpha_fields do
    canonical = canonical_key(char)
    requested_length = :proplists.get_value(canonical, skeleton_tokens, :not_found)
    field_length = length(field)

    cond do
      requested_length == :not_found ->
        [field | acc]

      field_length == requested_length ->
        [field | acc]

      field_length in [1, 2] and requested_length in [1, 2] ->
        [List.duplicate(char, requested_length) | acc]

      field_length > 2 and requested_length > 2 ->
        [List.duplicate(char, requested_length) | acc]

      true ->
        [field | acc]
    end
  end

  defp adjust_field_length([char | _rest], acc, skeleton_tokens)
       when char in @substitutable_zone_fields do
    {replacement_char, requested_length} =
      find_substitutable_field(@substitutable_zone_fields, skeleton_tokens)

    [List.duplicate(replacement_char, requested_length) | acc]
  end

  defp adjust_field_length([char | _rest] = field, acc, _skeleton_tokens)
       when char in @hms_fields do
    [field | acc]
  end

  defp adjust_field_length([char | _rest] = field, acc, skeleton_tokens) do
    field_length = length(field)
    requested_length = :proplists.get_value(char, skeleton_tokens, field_length)

    if field_length == requested_length do
      [field | acc]
    else
      [List.duplicate(char, requested_length) | acc]
    end
  end

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
      allowed = hd(prefs.allowed)
      do_replace_time_symbols(skeleton, preferred, allowed)
    else
      skeleton
    end
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

  defp time_preferences_for(locale_id) do
    locale_atom =
      if is_atom(locale_id), do: locale_id, else: String.to_atom(Kernel.to_string(locale_id))

    # Look up by locale name first, then by territory
    territory =
      case Localize.validate_locale(locale_atom) do
        {:ok, %{territory: t}} when not is_nil(t) -> t
        _ -> nil
      end

    Map.get(@time_preferences, locale_atom) ||
      (territory && Map.get(@time_preferences, territory)) ||
      Map.fetch!(@time_preferences, :"001")
  end
end
