defmodule Localize.Time do
  @moduledoc """
  Provides localized formatting of `Time` structs and time-like maps.

  Supports both full times (`%{hour: _, minute: _, second: _}`) and
  partial times (any map with one or more of `:hour`, `:minute`,
  `:second`). For a partial time a standard format, or no format, derives
  the skeleton from the fields present, with the hour in the locale's hour
  cycle; a skeleton or pattern that asks for a field the time does not
  have returns `Localize.DateTimeInvalidInputError`.

  Formats are defined in CLDR and described in
  [TR35](http://unicode.org/reports/tr35/tr35-dates.html).

  """

  import Kernel, except: [to_string: 1]
  import Localize.Utils.Helpers, only: [is_keyword_list: 1]

  @standard_formats [:short, :medium, :long, :full]
  @default_format :medium
  # Ordered by CLDR canonical skeleton order: hour, minute, second
  # A derived skeleton asks for the hour with TR35's `j`, the locale's
  # preferred hour symbol, so a partial time keeps the locale's hour cycle.
  @time_fields_ordered [{:hour, "j"}, {:minute, "m"}, {:second, "s"}]
  # Cycle-appropriate skeletons used when the locale carries a
  # `-u-hc-` override. Both 12-hour (`:hm` family) and 24-hour
  # (`:Hm` family) variants ship in every locale's
  # `available_formats`, with locale-correct AM/PM markers.
  @hc_override_skeletons %{
    {:short, :h12} => :hm,
    {:short, :h23} => :Hm,
    {:medium, :h12} => :hms,
    {:medium, :h23} => :Hms,
    {:long, :h12} => :hmsv,
    {:long, :h23} => :Hmsv,
    {:full, :h12} => :hmsv,
    {:full, :h23} => :Hmsv
  }

  # @time_field_names Enum.map(@time_fields_ordered, &elem(&1, 0))

  defguardp is_full_time(time)
            when is_map_key(time, :hour) and is_map_key(time, :minute) and
                   is_map_key(time, :second)

  defguardp has_time_field(time)
            when is_map_key(time, :hour) or is_map_key(time, :minute) or
                   is_map_key(time, :second)

  @doc """
  Formats a time according to a CLDR format pattern.

  ### Arguments

  * `time` is a `t:Time.t/0` or any map with one or more of
    `:hour`, `:minute`, `:second` keys.

  * `options` is a keyword list of options.

  ### Options

  * `:format` is a standard format name (`:short`, `:medium`,
    `:long`, `:full`), a format skeleton atom, a
    `Localize.DateTime.SemanticSkeleton` or a format pattern
    string. The default is `:medium` for full times. For a
    partial time a standard format, or no format, derives its
    skeleton from the fields present, with the hour in the
    locale's hour cycle or its `-u-hc-` override.

  * `:locale` is a locale identifier. The default is `:en`.

  * `:number_system` is a CLDR numbering system name (for example, `:thai`). All numeric fields render in that system; a `-u-nu-` locale extension may be used instead. The default is the locale's number system.

  * `:prefer` selects between CLDR `alt` variants. Accepts an
    atom or a list of atoms in priority order. Recognised values:
    `:unicode` / `:ascii` (NBSP and curly quotes vs ASCII) and
    `:standard` / `:variant` (a few locales publish two preferred
    forms). Examples: `prefer: :ascii`,
    `prefer: [:variant, :ascii]`. The default is
    `[:standard, :unicode]`.

  ### Returns

  * `{:ok, formatted_string}` on success.

  * `{:error, exception}` if the time cannot be formatted.

  ### Examples

      iex> Localize.Time.to_string(~T[14:30:00], locale: :en, prefer: :ascii)
      {:ok, "2:30:00 PM"}

      iex> Localize.Time.to_string(~T[14:30:00], format: :short, locale: :en, prefer: :ascii)
      {:ok, "2:30 PM"}

      iex> Localize.Time.to_string(%{hour: 14, minute: 30}, format: :hm, locale: :en, prefer: :ascii)
      {:ok, "2:30 PM"}

      iex> Localize.Time.to_string(%{hour: 14, minute: 30}, locale: :de)
      {:ok, "14:30"}

  """
  @spec to_string(map(), Keyword.t()) :: {:ok, String.t()} | {:error, Exception.t()}
  def to_string(time, options \\ []) do
    with {:ok, pattern, locale_id, formatter_options} <- formatting_plan(time, options) do
      Localize.DateTime.Formatter.format(time, pattern, locale_id, formatter_options)
    end
  end

  # Resolves the format pattern, locale, and formatter options for a
  # time — the shared front half of `to_string/2` and `to_parts/2`.
  defp formatting_plan(%{hour: _, minute: _, second: _} = time, options)
       when is_keyword_list(options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    format = Keyword.get(options, :format, @default_format)

    with {:ok, language_tag} <- Localize.validate_locale(locale),
         locale_id = language_tag.cldr_locale_id,
         hc_format = apply_hc_override(format, language_tag),
         hc_skeleton = apply_hc_to_skeleton(hc_format, language_tag),
         effective_format = strip_zone_for_time_struct(hc_skeleton, time, format, locale_id),
         {:ok, pattern} <- find_format(time, effective_format, locale_id, options) do
      formatter_options = options |> Map.new() |> Map.put_new(:locale, language_tag)
      {:ok, hour_cycle_pattern(pattern, format, language_tag), locale_id, formatter_options}
    end
  end

  # Partial time (has at least one time field but not all three).
  # Standard format atoms (`:short`/`:medium`/`:long`/`:full`) are
  # designed for full h/m/s times. For partial times we derive a
  # CLDR skeleton from the fields that are actually present
  # (`:h`, `:hm`, `:hms`, `:ms`, etc.) and resolve that instead.
  defp formatting_plan(time, options) when has_time_field(time) and is_keyword_list(options) do
    locale = Keyword.get(options, :locale, Localize.get_locale())
    format = Keyword.get(options, :format)

    with {:ok, language_tag} <- Localize.validate_locale(locale),
         locale_id = language_tag.cldr_locale_id,
         hc_format = apply_hc_to_skeleton(partial_format(format, time), language_tag),
         {:ok, pattern} <- find_format(time, hc_format, locale_id, options) do
      formatter_options = options |> Map.new() |> Map.put_new(:locale, language_tag)
      {:ok, hour_cycle_pattern(pattern, format, language_tag), locale_id, formatter_options}
    end
  end

  defp formatting_plan(_time, options) when not is_keyword_list(options),
    do: {:error, Localize.Utils.Helpers.invalid_options(options)}

  defp formatting_plan(_time, _options) do
    {:error, Localize.DateTimeInvalidInputError.exception(type: :time)}
  end

  # A standard format, or none, derives the skeleton from the fields
  # present; a pattern string, skeleton or semantic skeleton is used as
  # given. A `-u-hc-` override then applies to a skeleton either way.
  defp partial_format(format, time) when is_nil(format) or format in @standard_formats do
    derive_format_id(time)
  end

  defp partial_format(format, _time), do: format

  @doc """
  Same as `to_string/2` but raises on error.

  ### Arguments

  * `time` is a `t:Time.t/0` or any map with one or more of
    `:hour`, `:minute`, `:second` keys.

  * `options` is a keyword list of options.

  ### Options

  See `to_string/2` for the supported options.

  ### Returns

  * The formatted time as a string.

  * Raises an exception if the time cannot be formatted.

  ### Examples

      iex> Localize.Time.to_string!(~T[14:30:00], locale: :en, prefer: :ascii)
      "2:30:00 PM"

  """
  @spec to_string!(map(), Keyword.t()) :: String.t()
  def to_string!(time, options \\ []) do
    case to_string(time, options) do
      {:ok, string} -> string
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Formats a time into typed parts, mirroring ECMA-402's `formatToParts`.

  The parts concatenate to exactly the string `to_string/2` produces with the same options. Each pattern field is tagged with its type: `:hour`, `:minute`, `:second`, `:fractional_second`, `:day_period`, `:time_zone_name`, and `:literal` for separators.

  ### Arguments

  * `time` is a `t:Time.t/0` or any map with time keys.

  * `options` is a keyword list of options.

  ### Options

  See `to_string/2` for the supported options.

  ### Returns

  * `{:ok, parts}` where `parts` is a list of `%{type: atom(), value: String.t()}` maps.

  * `{:error, exception}` if the time cannot be formatted.

  ### Examples

      iex> Localize.Time.to_parts(~T[14:30:05], locale: :en, format: "HH:mm")
      {:ok,
       [
         %{type: :hour, value: "14"},
         %{type: :literal, value: ":"},
         %{type: :minute, value: "30"}
       ]}

  """
  @spec to_parts(map(), Keyword.t()) ::
          {:ok, [%{type: atom(), value: String.t()}]} | {:error, Exception.t()}
  def to_parts(time, options \\ []) do
    with {:ok, pattern, locale_id, formatter_options} <- formatting_plan(time, options) do
      Localize.DateTime.Formatter.format_to_parts(time, pattern, locale_id, formatter_options)
    end
  end

  @doc """
  Same as `to_parts/2` but raises on error.

  ### Arguments

  * `time` is a `t:Time.t/0` or any map with time keys.

  * `options` is a keyword list of options. See `to_parts/2`.

  ### Returns

  * A list of `%{type: atom(), value: String.t()}` maps.

  ### Raises

  * Raises an exception if the time cannot be formatted.

  ### Examples

      iex> Localize.Time.to_parts!(~T[14:30:05], locale: :en, format: "HH:mm") |> length()
      3

  """
  @spec to_parts!(map(), Keyword.t()) :: [%{type: atom(), value: String.t()}]
  def to_parts!(time, options \\ []) do
    case to_parts(time, options) do
      {:ok, parts} -> parts
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Returns the locale's preferred hour cycle.

  CLDR ships a per-territory (and per locale-territory) preference
  for how time-of-day is presented. The four cycles are:

  | Atom  | Range | Description                              |
  | :---- | :---- | :--------------------------------------- |
  | `:h11`| 0–11  | 12-hour clock, midnight is 0             |
  | `:h12`| 1–12  | 12-hour clock, midnight is 12            |
  | `:h23`| 0–23  | 24-hour clock, midnight is 0             |
  | `:h24`| 1–24  | 24-hour clock, midnight is 24            |

  A `-u-hc-` Unicode extension on the locale (e.g.
  `"fr-u-hc-h12"`) overrides the territory default.

  ### Arguments

  * `locale` is a locale name (atom or binary) or a
    `t:Localize.LanguageTag.t/0`.

  ### Returns

  * `{:ok, hour_cycle}` where `hour_cycle` is one of `:h11`,
    `:h12`, `:h23`, `:h24`.

  * `{:error, exception}` if the locale cannot be validated.

  ### Examples

      iex> Localize.Time.hour_format_from_locale(:ja)
      {:ok, :h23}

      iex> Localize.Time.hour_format_from_locale("en-AU")
      {:ok, :h12}

      iex> Localize.Time.hour_format_from_locale("fr-u-hc-h12")
      {:ok, :h12}

  """
  @spec hour_format_from_locale(Localize.LanguageTag.t() | atom() | String.t()) ::
          {:ok, :h11 | :h12 | :h23 | :h24} | {:error, Exception.t()}
  def hour_format_from_locale(%Localize.LanguageTag{locale: %{hc: hc}}) when not is_nil(hc) do
    {:ok, hc}
  end

  def hour_format_from_locale(%Localize.LanguageTag{cldr_locale_id: locale_id}) do
    prefs = Localize.DateTime.Format.Match.time_preferences_for(locale_id)
    {:ok, hour_cycle_from_symbol(prefs.preferred)}
  end

  def hour_format_from_locale(locale) do
    with {:ok, language_tag} <- Localize.validate_locale(locale) do
      hour_format_from_locale(language_tag)
    end
  end

  @doc """
  Same as `hour_format_from_locale/1` but raises on error.

  ### Examples

      iex> Localize.Time.hour_format_from_locale!(:ja)
      :h23

  """
  @spec hour_format_from_locale!(Localize.LanguageTag.t() | atom() | String.t()) ::
          :h11 | :h12 | :h23 | :h24
  def hour_format_from_locale!(locale) do
    case hour_format_from_locale(locale) do
      {:ok, cycle} -> cycle
      {:error, exception} -> raise exception
    end
  end

  defp hour_cycle_from_symbol("h"), do: :h12
  defp hour_cycle_from_symbol("K"), do: :h11
  defp hour_cycle_from_symbol("H"), do: :h23
  defp hour_cycle_from_symbol("k"), do: :h24

  # ── Format resolution ──────────────────────────────────────

  # When the locale carries a `-u-hc-` Unicode-extension override
  # (e.g. `"fr-u-hc-h12"`), remap a standard format atom (`:short`,
  # `:medium`, `:long`, `:full`) to the cycle-appropriate skeleton
  # in the locale's `available_formats`. Every locale ships
  # `:hm`/`:hms`/`:hmsv` (12-hour, with AM/PM) and `:Hm`/`:Hms`/
  # `:Hmsv` (24-hour) variants, so the lookup always resolves to a
  # locale-correct pattern. `:long`/`:full` map to the `v`-zone
  # variant (CLDR doesn't ship the `zzzz` full-zone variant for the
  # converse cycle), so the override-driven `:full` loses the
  # full-name timezone presentation in exchange for the requested
  # hour cycle. Non-standard formats (skeletons, literal patterns)
  # are returned unchanged.
  defp apply_hc_override(format, %{locale: %{hc: hc}})
       when format in @standard_formats and hc in [:h11, :h12, :h23, :h24] do
    cycle = if hc in [:h11, :h12], do: :h12, else: :h23
    Map.fetch!(@hc_override_skeletons, {format, cycle})
  end

  defp apply_hc_override(format, _language_tag), do: format

  # Applies a locale's `-u-hc-` Unicode-extension override to a
  # user-supplied skeleton atom. TR35's hour cycle replaces the
  # locale's preferred cycle, which a skeleton asks for with `j` or
  # `J`, so only those take the override's symbol (`:h11` → `K`,
  # `:h12` → `h`, `:h23` → `H`, `:h24` → `k`). `C` asks for the first
  # of the locale's allowed hour formats instead, which the override
  # does not change, as in ICU's pattern generator. An explicit `h` or
  # `H` keeps the cycle it names, and `apply_hour_cycle/3` then gives
  # the matched pattern the override's symbol within that cycle.
  #
  # `J` under a 12-hour cycle stays in the skeleton, so the matcher
  # still drops its day period; `apply_hour_cycle/3` gives the pattern
  # the cycle's symbol afterwards.
  #
  # Standard format atoms have already been remapped by
  # `apply_hc_override/2` above, and binary patterns are treated as
  # the user's deliberate assertion (the spec is silent on those),
  # so this only fires for non-standard skeleton atoms.
  defp apply_hc_to_skeleton(format, %{locale: %{hc: hc}})
       when is_atom(format) and hc in [:h11, :h12, :h23, :h24] do
    string = Atom.to_string(format)
    symbols = if hc in [:h23, :h24], do: ["j", "J"], else: ["j"]

    if format in @standard_formats or not String.contains?(string, symbols) do
      format
    else
      preferred = preferred_symbol_for_cycle(hc)

      substituted =
        Localize.DateTime.Format.Match.apply_hc_substitution(string, preferred, symbols)

      if substituted == string or substituted == "" do
        format
      else
        String.to_atom(substituted)
      end
    end
  end

  defp apply_hc_to_skeleton(format, _language_tag), do: format

  defp preferred_symbol_for_cycle(:h11), do: "K"
  defp preferred_symbol_for_cycle(:h12), do: "h"
  defp preferred_symbol_for_cycle(:h23), do: "H"
  defp preferred_symbol_for_cycle(:h24), do: "k"

  @same_cycle_hour %{"K" => "h", "h" => "K", "H" => "k", "k" => "H"}

  @doc false
  # TR35 part 1 gives each `-u-hc-` hour cycle its pattern symbol: h11 is K,
  # h12 h, h23 H and h24 k. A pattern resolved from a standard format or a
  # skeleton renders an hour of the same cycle with that symbol, as ICU's
  # pattern generator does: under `en-u-hc-h11` "h:mm a" is "K:mm a", while
  # "HH:mm" stays as it is. Quoted text is left alone, and a locale without
  # an `hc` keyword keeps the pattern.
  #
  # A `skeleton` that asks for the hour with `J` wants the cycle's hour with
  # no day period, so its pattern takes the cycle's symbol whichever cycle
  # it was written in: under `ja-u-hc-h11` "H:mm" is "K:mm", as in ICU.
  def apply_hour_cycle(pattern, locale, skeleton \\ nil)

  def apply_hour_cycle(pattern, locale, skeleton) when is_binary(pattern) do
    case hour_cycle_of(locale) do
      nil ->
        pattern

      hour_cycle ->
        replace_hour_symbol(pattern, preferred_symbol_for_cycle(hour_cycle), skeleton)
    end
  end

  def apply_hour_cycle(pattern, _locale, _skeleton), do: pattern

  defp hour_cycle_of(%Localize.LanguageTag{locale: %{hc: hour_cycle}})
       when hour_cycle in [:h11, :h12, :h23, :h24],
       do: hour_cycle

  defp hour_cycle_of(%Localize.LanguageTag{}), do: nil

  defp hour_cycle_of(locale) when is_binary(locale) or (is_atom(locale) and not is_nil(locale)) do
    case Localize.validate_locale(locale) do
      {:ok, language_tag} -> hour_cycle_of(language_tag)
      {:error, _reason} -> nil
    end
  end

  defp hour_cycle_of(_locale), do: nil

  # Quoted text alternates with pattern text around each quote, so the
  # even-numbered pieces are pattern.
  defp replace_hour_symbol(pattern, preferred, skeleton) do
    replaced =
      if hour_without_day_period?(skeleton),
        do: ["h", "H", "K", "k"],
        else: [Map.fetch!(@same_cycle_hour, preferred)]

    pattern
    |> String.split("'")
    |> Enum.with_index()
    |> Enum.map_join("'", fn
      {piece, index} when rem(index, 2) == 0 -> String.replace(piece, replaced, preferred)
      {piece, _index} -> piece
    end)
  end

  defp hour_without_day_period?(skeleton) when is_atom(skeleton),
    do: skeleton |> Atom.to_string() |> String.contains?("J")

  defp hour_without_day_period?(skeleton) when is_binary(skeleton),
    do: String.contains?(skeleton, "J")

  defp hour_without_day_period?(_skeleton), do: false

  # A literal pattern keeps the hour symbol it was written with.
  defp hour_cycle_pattern(pattern, format, _language_tag) when is_binary(format), do: pattern

  defp hour_cycle_pattern(pattern, format, language_tag),
    do: apply_hour_cycle(pattern, language_tag, format)

  # A `%Time{}` and a `%NaiveDateTime{}` both carry no zone
  # information by construction, so a standard format whose CLDR
  # pattern ends in a zone field can only render that field as an
  # empty string. Sidestep the problem at the source: strip zone
  # characters (`z`, `Z`, `O`, `v`, `V`, `x`, `X`) from the resolved
  # skeleton ID before resolving it to a pattern. The downstream
  # `resolve_skeleton/3` falls back to `best_match/3` if the stripped
  # skeleton is not present directly in the locale's
  # `available_formats` (e.g. ko's `:ahms`), so this works for every
  # locale without per-locale special-casing.
  #
  # Only fires for genuine `%Time{}` and `%NaiveDateTime{}` structs
  # and only when the user supplied a standard format atom (`:short`/
  # `:medium`/`:long`/`:full`); arbitrary maps with `:hour`/`:minute`/
  # `:second` may carry zone data the caller wants honoured, and
  # explicit skeletons are the user's deliberate choice.
  defp strip_zone_for_time_struct(format, %Time{}, original, locale_id)
       when original in @standard_formats do
    do_strip_zone_chars(format, locale_id)
  end

  defp strip_zone_for_time_struct(format, %NaiveDateTime{}, original, locale_id)
       when original in @standard_formats do
    do_strip_zone_chars(format, locale_id)
  end

  defp strip_zone_for_time_struct(format, _time, _original, _locale_id), do: format

  defp do_strip_zone_chars(format, locale_id) when format in @standard_formats do
    case Localize.DateTime.Format.time_formats(locale_id) do
      {:ok, %{} = formats} ->
        case Map.get(formats, format) do
          skeleton when is_atom(skeleton) -> strip_zone_chars_from_atom(skeleton, format)
          _ -> format
        end

      _ ->
        format
    end
  end

  defp do_strip_zone_chars(format, _locale_id) when is_atom(format) do
    strip_zone_chars_from_atom(format, format)
  end

  defp do_strip_zone_chars(format, _locale_id), do: format

  defp strip_zone_chars_from_atom(skeleton, fallback) do
    string = Atom.to_string(skeleton)
    stripped = String.replace(string, ~r/[zZOvVxX]/, "")

    cond do
      stripped == "" -> fallback
      stripped == string -> skeleton
      true -> String.to_atom(stripped)
    end
  end

  @doc false
  # The pattern `format` resolves to for `time`, as `to_string/2` resolves
  # it, including a `-u-hc-` override. `Localize.DateTime` resolves the `{0}`
  # half of a date-time wrapper here.
  def resolve_pattern(time, format, locale, options) do
    with {:ok, language_tag} <- Localize.validate_locale(locale),
         hour_cycle_format =
           format
           |> apply_hc_override(language_tag)
           |> apply_hc_to_skeleton(language_tag),
         {:ok, pattern} <-
           find_format(time, hour_cycle_format, language_tag.cldr_locale_id, options) do
      {:ok, hour_cycle_pattern(pattern, format, language_tag)}
    end
  end

  @doc false
  # A skeleton with its hour symbols replaced to honour a `-u-hc-` override
  # in `locale`, or the skeleton unchanged when there is none.
  def hour_cycle_skeleton(skeleton, locale) do
    case Localize.validate_locale(locale) do
      {:ok, language_tag} -> apply_hc_to_skeleton(skeleton, language_tag)
      {:error, _reason} -> skeleton
    end
  end

  defp find_format(_time, format, _locale_id, _options) when is_binary(format) do
    {:ok, format}
  end

  # A semantic skeleton names the meaning wanted rather than the fields; it
  # resolves to a classical skeleton and takes the same path from there.
  defp find_format(time, %Localize.DateTime.SemanticSkeleton{} = semantic, locale_id, options) do
    with {:ok, skeleton} <-
           Localize.DateTime.SemanticSkeleton.to_classical_skeleton(semantic, :gregorian) do
      skeleton
      |> resolve_skeleton(locale_id, options)
      |> Localize.DateTime.Formatter.explain_unresolved(time, skeleton)
    end
  end

  defp find_format(time, format, locale_id, options) when is_atom(format) do
    if format in @standard_formats and is_full_time(time) do
      Localize.DateTime.Format.resolve_format(:time, format, locale_id, :gregorian, options)
    else
      format
      |> resolve_skeleton(locale_id, options)
      |> Localize.DateTime.Formatter.explain_unresolved(time, format)
    end
  end

  defp find_format(_time, format, _locale_id, _options) do
    {:error, Localize.DateTimeFormatError.exception(format: format, reason: :invalid_format)}
  end

  # Fractional seconds (S) never participate in skeleton matching
  # per TR35: the S field is stripped before resolution and appended
  # to the seconds field of the resolved pattern afterwards.
  defp resolve_skeleton(skeleton, locale_id, options) when is_atom(skeleton) do
    {skeleton, fraction_count} =
      Localize.DateTime.Format.Match.split_fractional_seconds(skeleton)

    with {:ok, pattern} <- do_resolve_skeleton(skeleton, locale_id, options) do
      {:ok,
       Localize.DateTime.Format.Match.append_fractional_seconds(
         pattern,
         fraction_count,
         locale_id
       )}
    end
  end

  defp do_resolve_skeleton(skeleton, locale_id, options)
       when is_atom(skeleton) or is_binary(skeleton) do
    with {:ok, available} <-
           Localize.DateTime.Format.available_formats(locale_id, :gregorian) do
      case Map.get(available, skeleton) do
        nil ->
          resolve_skeleton_via_best_match(skeleton, locale_id, options)

        %{} = variant_map ->
          variant_map
          |> Localize.DateTime.Format.resolve_variant(options)
          |> variant_pattern_result(skeleton, locale_id)

        pattern when is_binary(pattern) ->
          {:ok, pattern}
      end
    end
  end

  # Ask `best_match` for the nearest skeleton when the exact
  # skeleton is not in `available_formats`. A combined date+time
  # match is not applicable for time-only formatting.
  defp resolve_skeleton_via_best_match(skeleton, locale_id, options) do
    case Localize.DateTime.Format.Match.best_match(skeleton, locale_id) do
      {:ok, matched_id} when is_atom(matched_id) ->
        with {:ok, pattern} <- resolve_skeleton(matched_id, locale_id, options) do
          # See the note in `Localize.Date`: TR35 adjusts the matched
          # format's field widths to those requested.
          {:ok, tokens} = Localize.DateTime.Format.Match.tokenize_skeleton(skeleton)
          Localize.DateTime.Format.Match.adjust_field_lengths(pattern, tokens, matched_id)
        end

      {:ok, {_date_id, _time_id}} ->
        {:error,
         Localize.DateTimeUnresolvedFormatError.exception(
           format: skeleton,
           locale: locale_id
         )}

      {:error, _} = error ->
        # See `Localize.Date`: fall back to TR35's append-item path before
        # reporting the skeleton unresolvable.
        case Localize.DateTime.Format.AppendItems.augment(
               skeleton,
               locale_id,
               :gregorian,
               options
             ) do
          {:ok, pattern} -> {:ok, pattern}
          _unresolvable -> error
        end
    end
  end

  defp variant_pattern_result(nil, skeleton, locale_id) do
    {:error,
     Localize.DateTimeUnresolvedFormatError.exception(
       format: skeleton,
       locale: locale_id
     )}
  end

  defp variant_pattern_result(pattern, _skeleton, _locale_id) do
    {:ok, pattern}
  end

  @doc false
  def derive_format_id(time) do
    @time_fields_ordered
    |> Enum.filter(fn {field, _symbol} -> Map.has_key?(time, field) end)
    |> Enum.map_join(fn {_field, symbol} -> symbol end)
    |> String.to_atom()
  end

  @doc """
  Parses a localized time string.

  Accepts any shape the locale accepts, including the locale's CLDR short,
  medium, long and full patterns and ISO 8601.

  ### Arguments

  * `string` is a string in any shape the locale accepts, including the
    locale's CLDR short, medium, long and full patterns and ISO 8601.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier. The default is the locale returned by
    `Localize.get_locale/0`.

  * `:as` is `:struct` or `:map`. `:map` returns only the fields the input
    actually carried, rather than completing them. The default is
    `:struct`.

  ### Returns

  * `{:ok, value}` where `value` is a `t:Time.t/0`, or

  * `{:error, exception}` if the string does not parse, or a
    `t:Localize.InvalidValueError.t/0` if `string` is not a string or an
    option is malformed.

  ### Examples

      iex> Localize.Time.parse("14:30", locale: :de)
      {:ok, ~T[14:30:00]}

      iex> Localize.Time.parse("2:30 PM", locale: :en)
      {:ok, ~T[14:30:00]}

  """
  @spec parse(String.t(), Keyword.t()) :: {:ok, Time.t()} | {:error, Exception.t()}
  def parse(string, options \\ []) do
    with :ok <- Localize.DateTime.ParseOptions.validate(string, options) do
      Localize.Time.Parser.parse(string, options)
    end
  end
end
