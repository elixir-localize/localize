defmodule Localize do
  @moduledoc """
  Locale-aware formatting, validation, and data access built on the
  Unicode CLDR repository.

  Localize consolidates the functionality of the `ex_cldr_*` library
  family into a single package with no compile-time backend
  configuration. All CLDR data is loaded at runtime from ETF and JSON
  files and cached in `:persistent_term` on first access.

  ## Domain modules

  * `Localize.Number` — format numbers, decimals, percentages, and
    currencies.

  * `Localize.Date` — format dates using CLDR calendar patterns.

  * `Localize.Time` — format times using CLDR calendar patterns.

  * `Localize.DateTime` — format date-times with combined date and
    time patterns.

  * `Localize.Interval` — format date, time, and datetime intervals.

  * `Localize.Unit` — format units of measure with plural-aware
    patterns (e.g., "3 kilometers", "1.5 hours").

  * `Localize.List` — format lists with locale-appropriate
    conjunctions and disjunctions (e.g., "a, b, and c").

  * `Localize.Currency` — currency metadata, validation, and
    territory-to-currency mapping.

  * `Localize.Territory` — territory display names, containment,
    subdivisions, and emoji flags.

  * `Localize.Language` — language display names.

  * `Localize.Collation` — locale-sensitive string sorting using the
    Unicode Collation Algorithm.

  * `Localize.LocaleDisplay` — full locale display names
    (e.g., "English (United States)").

  * `Localize.Calendar` — calendar era names, day/month names, and
    day period names.

  ## Locale management

  Localize maintains a per-process current locale and an
  application-wide default locale:

  * `get_locale/0` — returns the current process locale, falling
    back to `default_locale/0`.

  * `put_locale/1` — sets the current process locale.

  * `with_locale/2` — executes a function with a temporary locale.

  * `default_locale/0` — returns the application-wide default,
    resolved from environment variables and application config.

  * `put_default_locale/1` — overrides the application-wide default.

  All formatting functions default their `:locale` option to
  `get_locale/0` when no locale is explicitly provided.

  ## This module

  This module also provides text formatting helpers (`quote/2`,
  `ellipsis/2`), validators for locales, territories, scripts,
  calendars, number systems, currencies, and measurement systems,
  and accessors for known locale names and territory lists.

  ## Optional NIF

  An optional NIF-based implementation of selected algorithms
  (currently Unicode normalisation and collation sort-key generation)
  can be enabled by setting `LOCALIZE_NIF=true` at compile time. See
  `Localize.Nif` for details.

  """

  require Logger

  # ── Process locale management ──────────────────────────────────

  @typedoc "A locale identifier atom or a language tag struct."
  @type locale :: atom() | Localize.LanguageTag.t()

  @locale_key :localize_locale
  @default_locale_key :localize_default_locale

  @doc """
  Returns the application-wide default locale as a
  `t:Localize.LanguageTag.t/0`.

  The default locale is resolved once on first access using the
  following precedence chain:

  1. A value previously set via `put_default_locale/1`.

  2. The `LOCALIZE_DEFAULT_LOCALE` environment variable.

  3. The `:default_locale` key in the `:localize` application
     environment (e.g., `config :localize, default_locale: :fr`).

  4. The `LANG` environment variable (e.g., `"en_US.UTF-8"`),
     with the charset suffix stripped.

  5. `:en` as a final fallback.

  The resolved locale is validated via `validate_locale/1` and
  cached in `:persistent_term` so subsequent calls are free. If
  any source provides an invalid locale, a warning is logged and
  the next source in the chain is tried.

  ### Returns

  * A `t:Localize.LanguageTag.t/0`.

  ### Examples

      iex> %Localize.LanguageTag{} = Localize.default_locale()
      iex> Localize.default_locale().cldr_locale_id
      :en

  """
  @spec default_locale() :: Localize.LanguageTag.t()
  def default_locale do
    case :persistent_term.get(@default_locale_key, :not_set) do
      :not_set -> resolve_and_cache_default_locale()
      language_tag -> language_tag
    end
  end

  @doc """
  Sets the application-wide default locale.

  The locale is validated via `validate_locale/1` and the
  resulting `t:Localize.LanguageTag.t/0` is cached in
  `:persistent_term`. This value is used as the fallback when
  no process-level locale has been set via `put_locale/1`.

  ### Arguments

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0`.

  ### Returns

  * `{:ok, language_tag}` on success.

  * `{:error, exception}` if the locale is not valid.

  ### Examples

      iex> {:ok, tag} = Localize.put_default_locale(:fr)
      iex> tag.cldr_locale_id
      :fr
      iex> Localize.default_locale().cldr_locale_id
      :fr
      iex> {:ok, _} = Localize.put_default_locale(:en)

  """
  @spec put_default_locale(Localize.LanguageTag.t() | atom() | String.t()) ::
          {:ok, Localize.LanguageTag.t()} | {:error, Exception.t()}
  def put_default_locale(%Localize.LanguageTag{} = language_tag) do
    :persistent_term.put(@default_locale_key, language_tag)
    {:ok, language_tag}
  end

  def put_default_locale(locale) do
    with {:ok, language_tag} <- validate_locale(locale) do
      :persistent_term.put(@default_locale_key, language_tag)
      {:ok, language_tag}
    end
  end

  @doc """
  Returns the locale for the current process as a
  `t:Localize.LanguageTag.t/0`.

  If no locale has been set for the current process via
  `put_locale/1`, returns `default_locale/0`.

  ### Returns

  * A `t:Localize.LanguageTag.t/0`.

  ### Examples

      iex> %Localize.LanguageTag{} = Localize.get_locale()
      iex> Localize.get_locale().cldr_locale_id
      :en

  """
  @spec get_locale() :: Localize.LanguageTag.t()
  def get_locale do
    Process.get(@locale_key) || default_locale()
  end

  @doc """
  Sets the locale for the current process.

  The locale is validated via `validate_locale/1` and stored
  in the process dictionary as a `t:Localize.LanguageTag.t/0`.
  It is used as the default by all formatting functions in this
  process. It does not propagate to spawned processes — use
  `with_locale/2` or explicitly pass the locale when spawning
  tasks.

  ### Arguments

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0`.

  ### Returns

  * `{:ok, language_tag}` on success. The previous locale (or
    `nil`) can be retrieved from the process dictionary before
    calling this function if needed.

  * `{:error, exception}` if the locale is not valid.

  ### Examples

      iex> {:ok, _} = Localize.put_locale(:de)
      iex> Localize.get_locale().cldr_locale_id
      :de
      iex> {:ok, _} = Localize.put_locale(:en)

  """
  @spec put_locale(Localize.LanguageTag.t() | atom() | String.t()) ::
          {:ok, Localize.LanguageTag.t()} | {:error, Exception.t()}
  def put_locale(%Localize.LanguageTag{} = language_tag) do
    Process.put(@locale_key, language_tag)
    {:ok, language_tag}
  end

  def put_locale(locale) do
    with {:ok, language_tag} <- validate_locale(locale) do
      Process.put(@locale_key, language_tag)
      {:ok, language_tag}
    end
  end

  @doc """
  Executes a function with a temporary process locale.

  Sets the process locale to `locale`, executes `fun`, then
  restores the previous locale regardless of whether `fun`
  raises or throws.

  ### Arguments

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0`.

  * `fun` is a zero-arity function to execute.

  ### Returns

  * The return value of `fun`.

  * Raises if the locale is not valid.

  ### Examples

      iex> Localize.with_locale(:ja, fn -> Localize.get_locale().cldr_locale_id end)
      :ja

      iex> Localize.get_locale().cldr_locale_id
      :en

  """
  @spec with_locale(Localize.LanguageTag.t() | atom() | String.t(), (-> result)) ::
          result
        when result: any()
  def with_locale(locale, fun) when is_function(fun, 0) do
    previous = Process.get(@locale_key)

    case put_locale(locale) do
      {:ok, _} ->
        try do
          fun.()
        after
          if previous do
            Process.put(@locale_key, previous)
          else
            Process.delete(@locale_key)
          end
        end

      {:error, _} = error ->
        raise "invalid locale: #{inspect(error)}"
    end
  end

  defp resolve_and_cache_default_locale do
    language_tag =
      try_locale_from_env("LOCALIZE_DEFAULT_LOCALE") ||
        try_locale_from_app_config() ||
        try_locale_from_env("LANG") ||
        validate_locale(:en) |> elem(1)

    :persistent_term.put(@default_locale_key, language_tag)
    language_tag
  end

  defp try_locale_from_env(var_name) do
    case System.get_env(var_name) do
      nil ->
        nil

      raw ->
        locale_id =
          raw
          |> String.split(".")
          |> hd()
          |> Localize.Locale.locale_id_from_posix()

        case validate_locale(locale_id) do
          {:ok, tag} ->
            tag

          {:error, exception} ->
            Logger.warning(
              "#{var_name}=#{inspect(raw)} is not a valid locale: " <>
                Exception.message(exception),
              domain: :localize
            )

            nil
        end
    end
  end

  defp try_locale_from_app_config do
    case Application.get_env(:localize, :default_locale) do
      nil ->
        nil

      locale ->
        case validate_locale(locale) do
          {:ok, tag} ->
            tag

          {:error, exception} ->
            Logger.warning(
              "config :localize, default_locale: #{inspect(locale)} is not a valid locale: " <>
                Exception.message(exception),
              domain: :localize
            )

            nil
        end
    end
  end

  # ── Text formatting ──────────────────────────────────────────

  @doc """
  Wraps a string in locale-specific quotation marks.

  Uses the CLDR delimiters data for the given locale to apply
  the appropriate opening and closing quotation marks.

  ### Arguments

  * `string` is the text to quote.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0`. The default is `:en`.

  * `:style` is either `:default` or `:variant`. The default
    style uses the primary quotation marks for the locale. The
    `:variant` style uses the alternate (nested) quotation marks.

  ### Returns

  * `{:ok, quoted_string}` where `quoted_string` has locale-specific
    quotation marks added.

  * `{:error, exception}` if the locale data cannot be loaded.

  ### Examples

      iex> Localize.quote("Hello")
      {:ok, "\u201CHello\u201D"}

      iex> Localize.quote("Hello", style: :variant)
      {:ok, "\u2018Hello\u2019"}

  """
  @spec quote(String.t(), Keyword.t()) :: {:ok, String.t()} | {:error, Exception.t()}
  def quote(string, options \\ []) when is_binary(string) do
    locale = Keyword.get(options, :locale, get_locale())
    style = Keyword.get(options, :style, :default)
    locale_id = to_locale_id(locale)

    with {:ok, delimiters} <- Localize.Locale.get(locale_id, [:delimiters]) do
      open = get_in(delimiters, [:quotation_start, style]) || ""
      close = get_in(delimiters, [:quotation_end, style]) || ""
      {:ok, open <> string <> close}
    end
  end

  @doc """
  Adds locale-specific ellipsis characters to a string or between
  two strings.

  Uses the CLDR ellipsis patterns for the given locale.

  ### Arguments

  * `string` is either a single string or a list of two strings
    to join with an ellipsis between them.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0`. The default is `:en`.

  * `:location` determines where the ellipsis is placed. Valid
    values are `:after` (append), `:before` (prepend), and
    `:between` (medial, requires a two-element list). The default
    is `:after` for a single string and `:between` for a list.

  * `:format` is either `:sentence` or `:word`. The `:word` format
    includes a space between the text and the ellipsis. The default
    is `:sentence`.

  ### Returns

  * `{:ok, ellipsized_string}` with locale-specific ellipsis applied.

  * `{:error, exception}` if the locale data cannot be loaded.

  ### Examples

      iex> Localize.ellipsis("And so on")
      {:ok, "And so on\u2026"}

      iex> Localize.ellipsis("And so on", location: :before)
      {:ok, "\u2026And so on"}

      iex> Localize.ellipsis(["start", "end"])
      {:ok, "start\u2026end"}

      iex> Localize.ellipsis("And so on", format: :word)
      {:ok, "And so on \u2026"}

  """
  @spec ellipsis(String.t() | [String.t()], Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def ellipsis(string, options \\ []) do
    locale = Keyword.get(options, :locale, get_locale())
    format = Keyword.get(options, :format, :sentence)
    location = Keyword.get(options, :location, default_ellipsis_location(string))
    locale_id = to_locale_id(locale)

    with {:ok, ellipsis_chars} <- Localize.Locale.get(locale_id, [:ellipsis]) do
      result = apply_ellipsis(string, ellipsis_chars, location, format)
      {:ok, result}
    end
  end

  defp default_ellipsis_location(list) when is_list(list), do: :between
  defp default_ellipsis_location(_string), do: :after

  defp apply_ellipsis([string_1, string_2], chars, :between, :word) do
    [string_1, string_2]
    |> Localize.Substitution.substitute(chars.word_medial)
    |> :erlang.iolist_to_binary()
  end

  defp apply_ellipsis([string_1, string_2], chars, :between, :sentence) do
    [string_1, string_2]
    |> Localize.Substitution.substitute(chars.medial)
    |> :erlang.iolist_to_binary()
  end

  defp apply_ellipsis(string, chars, :after, :word) when is_binary(string) do
    string
    |> Localize.Substitution.substitute(chars.word_final)
    |> :erlang.iolist_to_binary()
  end

  defp apply_ellipsis(string, chars, :after, :sentence) when is_binary(string) do
    string
    |> Localize.Substitution.substitute(chars.final)
    |> :erlang.iolist_to_binary()
  end

  defp apply_ellipsis(string, chars, :before, :word) when is_binary(string) do
    string
    |> Localize.Substitution.substitute(chars.word_initial)
    |> :erlang.iolist_to_binary()
  end

  defp apply_ellipsis(string, chars, :before, :sentence) when is_binary(string) do
    string
    |> Localize.Substitution.substitute(chars.initial)
    |> :erlang.iolist_to_binary()
  end

  # ── Data accessors (Tier 1) ────────────────────────────────

  @doc """
  Returns the list of supported locales configured via
  `config :localize, supported_locales: [...]`.

  If no `:supported_locales` option is configured, returns `nil`.
  If configured with an empty list, returns `[]`.

  The returned list contains canonical CLDR locale ID atoms,
  resolved and validated at application startup.

  ### Returns

  * A list of locale ID atoms, or `nil` if not configured.

  ### Examples

      iex> is_list(Localize.supported_locales()) or is_nil(Localize.supported_locales())
      true

  """
  @spec supported_locales() :: [atom()] | nil
  def supported_locales do
    :persistent_term.get(:localize_supported_locales, nil)
  end

  @doc """
  Returns a list of all known CLDR locale name atoms.

  ### Returns

  * A list of locale name atoms.

  ### Examples

      iex> locales = Localize.all_locale_names()
      iex> :en in locales
      true

  """
  @spec all_locale_names() :: [atom()]
  def all_locale_names do
    Localize.SupplementalData.all_locale_ids()
  end

  @doc """
  Returns whether a locale name is available in the CLDR
  repository.

  ### Arguments

  * `locale_name` is a locale identifier atom or string.

  ### Returns

  * `true` if the locale is available in CLDR.

  * `false` otherwise.

  ### Examples

      iex> Localize.available_locale_name?(:en)
      true

      iex> Localize.available_locale_name?(:zzzz)
      false

  """
  @spec available_locale_name?(atom() | String.t()) :: boolean()
  def available_locale_name?(locale_name) when is_atom(locale_name) do
    locale_name in all_locale_names()
  end

  def available_locale_name?(locale_name) when is_binary(locale_name) do
    available_locale_name?(String.to_atom(locale_name))
  end

  @doc """
  Returns a list of all known CLDR calendar type atoms.

  ### Returns

  * A list of calendar type atoms.

  ### Examples

      iex> calendars = Localize.known_calendars()
      iex> :gregorian in calendars
      true

  """
  @spec known_calendars() :: [atom()]
  def known_calendars do
    Localize.Calendar.known_calendars()
  end

  @doc """
  Returns a list of all known CLDR number system atoms.

  ### Returns

  * A list of number system atoms.

  ### Examples

      iex> systems = Localize.known_number_systems()
      iex> :latn in systems
      true

  """
  @spec known_number_systems() :: [atom()]
  def known_number_systems do
    Localize.Number.System.known_number_systems()
  end

  # ── Validation (Tier 2) ──────────────────────────────────────

  @doc """
  Validates a territory code.

  Normalises the territory code and checks it against the CLDR
  validity data. Integer codes are zero-padded (e.g., `1` becomes
  `"001"`). String codes are uppercased.

  ### Arguments

  * `territory` is a territory code atom, string, or integer.

  ### Returns

  * `{:ok, territory_atom}` where `territory_atom` is the
    normalised territory atom.

  * `{:error, exception}` if the territory is not known.

  ### Examples

      iex> Localize.validate_territory(:US)
      {:ok, :US}

      iex> Localize.validate_territory("us")
      {:ok, :US}

      iex> Localize.validate_territory(:ZZZZ)
      {:error, %Localize.UnknownTerritoryError{territory: :ZZZZ}}

  """
  @spec validate_territory(atom() | String.t() | integer()) ::
          {:ok, atom()} | {:error, Exception.t()}
  def validate_territory(territory) do
    case Localize.Validity.Territory.validate(territory) do
      {:ok, nil, _status} ->
        {:error, Localize.UnknownTerritoryError.exception(territory: territory)}

      {:ok, territory_atom, _status} ->
        {:ok, territory_atom}

      {:error, _} ->
        {:error, Localize.UnknownTerritoryError.exception(territory: territory)}
    end
  end

  @doc """
  Validates a script code.

  Normalises the script code (capitalised form, e.g., `"Latn"`)
  and checks it against the CLDR validity data.

  ### Arguments

  * `script` is a script code atom or string.

  ### Returns

  * `{:ok, script_atom}` where `script_atom` is the normalised
    script atom.

  * `{:error, exception}` if the script is not known.

  ### Examples

      iex> Localize.validate_script(:Latn)
      {:ok, :Latn}

      iex> Localize.validate_script("latn")
      {:ok, :Latn}

      iex> Localize.validate_script(:Xyzq)
      {:error, %Localize.UnknownScriptError{script: :Xyzq}}

  """
  @spec validate_script(atom() | String.t()) ::
          {:ok, atom()} | {:error, Exception.t()}
  def validate_script(script) do
    case Localize.Validity.Script.validate(script) do
      {:ok, nil, _status} ->
        {:error, Localize.UnknownScriptError.exception(script: script)}

      {:ok, script_atom, _status} ->
        {:ok, script_atom}

      {:error, _} ->
        {:error, Localize.UnknownScriptError.exception(script: script)}
    end
  end

  @doc """
  Validates a calendar name.

  Checks the calendar against the list of known CLDR calendars.
  The string `"gregory"` is accepted as an alias for `:gregorian`.

  ### Arguments

  * `calendar` is a calendar name atom or string.

  ### Returns

  * `{:ok, calendar_atom}` where `calendar_atom` is the
    normalised calendar atom.

  * `{:error, exception}` if the calendar is not known.

  ### Examples

      iex> Localize.validate_calendar(:gregorian)
      {:ok, :gregorian}

      iex> Localize.validate_calendar("persian")
      {:ok, :persian}

      iex> Localize.validate_calendar(:unknown)
      {:error, %Localize.UnknownCalendarError{calendar: :unknown}}

  """
  @spec validate_calendar(atom() | String.t()) ::
          {:ok, atom()} | {:error, Exception.t()}
  def validate_calendar(calendar) when is_binary(calendar) do
    validate_calendar(normalize_calendar(calendar))
  end

  def validate_calendar(calendar) when is_atom(calendar) do
    if calendar in known_calendars() do
      {:ok, calendar}
    else
      {:error, Localize.UnknownCalendarError.exception(calendar: calendar)}
    end
  end

  defp normalize_calendar("gregory"), do: :gregorian

  defp normalize_calendar(name) when is_binary(name) do
    String.to_atom(String.downcase(name))
  end

  @doc """
  Validates a number system name.

  Checks the number system against the list of known CLDR
  number systems.

  ### Arguments

  * `number_system` is a number system name atom or string.

  ### Returns

  * `{:ok, number_system_atom}` where `number_system_atom` is the
    normalised number system atom.

  * `{:error, exception}` if the number system is not known.

  ### Examples

      iex> Localize.validate_number_system(:latn)
      {:ok, :latn}

      iex> Localize.validate_number_system("arab")
      {:ok, :arab}

      iex> Localize.validate_number_system(:unknown)
      {:error, %Localize.UnknownNumberSystemError{number_system: :unknown}}

  """
  @spec validate_number_system(atom() | String.t()) ::
          {:ok, atom()} | {:error, Exception.t()}
  def validate_number_system(number_system) when is_binary(number_system) do
    validate_number_system(String.to_atom(number_system))
  end

  def validate_number_system(number_system) when is_atom(number_system) do
    if number_system in known_number_systems() do
      {:ok, number_system}
    else
      {:error, Localize.UnknownNumberSystemError.exception(number_system: number_system)}
    end
  end

  @doc """
  Validates a territory subdivision code.

  Normalises the subdivision code (lowercased) and checks it
  against the CLDR validity data.

  ### Arguments

  * `subdivision` is a subdivision code atom or string.

  ### Returns

  * `{:ok, subdivision_atom}` where `subdivision_atom` is the
    normalised subdivision atom.

  * `{:error, exception}` if the subdivision is not known.

  ### Examples

      iex> Localize.validate_territory_subdivision(:usca)
      {:ok, :usca}

      iex> Localize.validate_territory_subdivision("gbeng")
      {:ok, :gbeng}

      iex> Localize.validate_territory_subdivision(:zzzzz)
      {:error, %Localize.UnknownSubdivisionError{subdivision: :zzzzz}}

  """
  @spec validate_territory_subdivision(atom() | String.t()) ::
          {:ok, atom()} | {:error, Exception.t()}
  def validate_territory_subdivision(subdivision) do
    case Localize.Validity.Subdivision.validate(subdivision) do
      {:ok, nil, _status} ->
        {:error, Localize.UnknownSubdivisionError.exception(subdivision: subdivision)}

      {:ok, subdivision_atom, _status} ->
        {:ok, subdivision_atom}

      {:error, _} ->
        {:error, Localize.UnknownSubdivisionError.exception(subdivision: subdivision)}
    end
  end

  @known_measurement_systems [:metric, :us, :uk]

  @doc """
  Validates a measurement system type.

  ### Arguments

  * `system` is a measurement system atom or string. Valid values
    are `:metric`, `:us`, and `:uk`.

  ### Returns

  * `{:ok, system_atom}` where `system_atom` is the measurement
    system atom.

  * `{:error, exception}` if the measurement system is not known.

  ### Examples

      iex> Localize.validate_measurement_system(:metric)
      {:ok, :metric}

      iex> Localize.validate_measurement_system("us")
      {:ok, :us}

      iex> Localize.validate_measurement_system(:imperial)
      {:error, %Localize.UnknownMeasurementSystemError{measurement_system: :imperial}}

  """
  @spec validate_measurement_system(atom() | String.t()) ::
          {:ok, atom()} | {:error, Exception.t()}
  def validate_measurement_system(system) when is_binary(system) do
    validate_measurement_system(String.to_atom(String.downcase(system)))
  end

  def validate_measurement_system(system) when is_atom(system) do
    if system in @known_measurement_systems do
      {:ok, system}
    else
      {:error, Localize.UnknownMeasurementSystemError.exception(measurement_system: system)}
    end
  end

  # ── Locale validation ──────────────────────────────────────

  @doc """
  Validates a locale identifier or language tag.

  Ensures that the given locale can be resolved to a known CLDR
  locale. When given a binary locale identifier, it is parsed into
  a `Localize.LanguageTag`. When given an existing language tag
  whose `:cldr_locale_id` is not yet populated, a best-match
  resolution is attempted using `Localize.LanguageTag.best_match/2`.

  ## Locale resolution

  The `:cldr_locale_id` field on the returned language tag is
  derived by matching the parsed tag against a list of candidate
  locale IDs:

  * If `config :localize, supported_locales: [...]` is
    configured, the candidate list is the resolved supported
    locales (the union of `:supported_locales` and
    `:preload_locales`). This restricts matching to only the
    locales your application explicitly supports.

  * If `:supported_locales` is not configured, the candidate
    list is all ~766 CLDR locale IDs.

  Validated locale results are cached in an ETS table so
  repeated calls with the same identifier are fast (~1µs).

  ### Arguments

  * `locale` is a locale identifier binary, an atom, or a
    `t:Localize.LanguageTag.t/0`.

  ### Returns

  * `{:ok, language_tag}` where `language_tag` is a
    `t:Localize.LanguageTag.t/0` with a populated `:cldr_locale_id`.

  * `{:error, Localize.InvalidLocaleError.t()}` if the locale
    identifier cannot be parsed into a valid language tag.

  * `{:error, Localize.UnknownLocaleError.t()}` if the locale
    parses successfully but does not match any known CLDR locale
    (or any supported locale, when configured).

  ### Examples

      iex> {:ok, tag} = Localize.validate_locale("en")
      iex> tag.cldr_locale_id
      :en

  """
  @locale_cache_table :localize_locale_cache

  @spec validate_locale(Localize.LanguageTag.t() | String.t() | atom()) ::
          {:ok, Localize.LanguageTag.t()} | {:error, Exception.t()}

  def validate_locale(%Localize.LanguageTag{cldr_locale_id: cldr_locale_id} = language_tag)
      when not is_nil(cldr_locale_id) do
    maybe_restrict_to_supported(language_tag)
  end

  def validate_locale(%Localize.LanguageTag{cldr_locale_id: nil} = language_tag) do
    resolve_cldr_locale(language_tag)
  end

  def validate_locale(locale_id) when is_binary(locale_id) do
    cache_key = locale_id |> String.replace("_", "-") |> String.downcase()

    case locale_cache_lookup(cache_key) do
      {:ok, _tag} = cached ->
        cached

      :miss ->
        result =
          case Localize.LanguageTag.new(locale_id) do
            {:ok, %Localize.LanguageTag{cldr_locale_id: cldr_locale_id} = language_tag}
            when not is_nil(cldr_locale_id) ->
              maybe_restrict_to_supported(language_tag)

            {:ok, %Localize.LanguageTag{cldr_locale_id: nil} = language_tag} ->
              resolve_cldr_locale(language_tag)

            {:error, _reason} ->
              {:error, Localize.InvalidLocaleError.exception(locale_id: locale_id)}
          end

        locale_cache_store(cache_key, result)
        result
    end
  end

  def validate_locale(locale_id) when is_atom(locale_id) do
    validate_locale(Atom.to_string(locale_id))
  end

  defp locale_cache_lookup(cache_key) do
    case :ets.lookup(@locale_cache_table, cache_key) do
      [{^cache_key, result}] -> result
      [] -> :miss
    end
  rescue
    ArgumentError -> :miss
  end

  defp locale_cache_store(cache_key, {:ok, _tag} = result) do
    :ets.insert(@locale_cache_table, {cache_key, result})
  rescue
    ArgumentError -> :ok
  end

  defp locale_cache_store(_cache_key, {:error, _}), do: :ok

  # When supported_locales is configured and the tag's cldr_locale_id
  # was already set by LanguageTag.new, check whether it's in the
  # supported list. If not, re-resolve via best_match against the
  # supported list to find the closest supported locale.
  defp maybe_restrict_to_supported(%Localize.LanguageTag{cldr_locale_id: cldr_locale_id} = tag) do
    case :persistent_term.get(:localize_supported_locales, nil) do
      list when is_list(list) and list != [] ->
        if cldr_locale_id in list do
          {:ok, tag}
        else
          resolve_cldr_locale(tag)
        end

      _ ->
        {:ok, tag}
    end
  end

  defp resolve_cldr_locale(%Localize.LanguageTag{} = language_tag) do
    locale_ids =
      case :persistent_term.get(:localize_supported_locales, nil) do
        list when is_list(list) and list != [] -> list
        _ -> Localize.SupplementalData.all_locale_ids()
      end

    case Localize.LanguageTag.best_match(language_tag, locale_ids) do
      {:ok, cldr_locale_id, _score} ->
        {:ok, %{language_tag | cldr_locale_id: cldr_locale_id}}

      {:error, _} ->
        locale_id = Localize.LanguageTag.to_string(language_tag)
        {:error, Localize.UnknownLocaleError.exception(locale_id: locale_id)}
    end
  end

  defdelegate to_locale_id(locale), to: Localize.Locale
end
