defmodule Localize do
  @moduledoc """
  Locale-aware formatting, validation, and data access built on the
  Unicode CLDR repository.

  Localize consolidates the functionality of the `ex_cldr_*` library
  family into a single package with no compile-time backend
  configuration. All CLDR data is loaded at runtime from ETF and JSON
  files and cached in `:persistent_term` on first access.

  ## Primary usage modules

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

  * `Localize.Locale.LocaleDisplay` — full locale display names
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
  alias Localize.Locale

  @typedoc "A locale identifier. That is, known to CLDR"
  @type locale_id :: atom()

  @typedoc "A locale identifier atom or a language tag struct."
  @type locale :: locale_id | Localize.LanguageTag.t()

  @locale_key :localize_locale
  @default_locale_key {:localize, :default_locale}

  @coverage_levels [:basic, :moderate, :modern]
  @locale_cache_table :localize_locale_cache

  @version_key {:localize, :version}

  @doc """
  Returns the CLDR version this build of Localize targets.

  The version is a `t:Version.t/0` whose major and minor components
  come from `priv/localize/version` (the CLDR release version) and
  whose patch component comes from `priv/localize/localize_patch_version`
  (Localize's per-release patch counter).

  The value is read once on first access and cached in
  `:persistent_term`.

  ### Returns

  * A `t:Version.t/0` representing the CLDR version.

  ### Examples

      iex> %Version{} = Localize.version()

  """
  @spec version() :: Version.t()
  def version do
    case :persistent_term.get(@version_key, :not_set) do
      :not_set ->
        version = read_version()
        :persistent_term.put(@version_key, version)
        version

      version ->
        version
    end
  end

  defp read_version do
    cldr_version =
      :localize
      |> Application.app_dir("priv/localize/version")
      |> read_trimmed("0.0")

    patch_raw =
      :localize
      |> Application.app_dir("priv/localize/localize_patch_version")
      |> read_trimmed("0")

    patch =
      case String.split(patch_raw, ":", parts: 2) do
        [^cldr_version, patch] -> patch
        [patch_only] -> patch_only
        _ -> "0"
      end

    # CLDR sometimes records only the major version (e.g. `"48"`)
    # in `aliases.json`, so the on-disk version file may be either
    # `"48"` or `"48.2"`. `Version.parse/1` requires three
    # components, so pad missing minor/patch components with `0`.
    case Version.parse(normalize_semver(cldr_version, patch)) do
      {:ok, version} -> version
      :error -> Version.parse!("0.0.0")
    end
  end

  defp normalize_semver(cldr_version, patch) do
    case String.split(cldr_version, ".") do
      [major] -> "#{major}.0.#{patch}"
      [major, minor] -> "#{major}.#{minor}.#{patch}"
      [major, minor, _existing_patch | _rest] -> "#{major}.#{minor}.#{patch}"
    end
  end

  defp read_trimmed(path, default) do
    case File.read(path) do
      {:ok, content} -> String.trim(content)
      {:error, _} -> default
    end
  end

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

      other ->
        other
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
    if raw = System.get_env(var_name) do
      locale_id = locale_from_env_var(raw)

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
    if locale = Application.get_env(:localize, :default_locale) do
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

  defp locale_from_env_var(raw) do
    raw
    |> String.split(".")
    |> hd()
    |> Localize.Locale.locale_id_from_posix()
  end

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
    locale_id = Locale.to_locale_id(locale)

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
    locale_id = Locale.to_locale_id(locale)

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

  @doc """
  Returns the list of supported locales configured via
  `config :localize, supported_locales: [...]` or
  `Localize.all_locale_ids/0`.

  The returned list contains canonical CLDR locale ID atoms,
  resolved and validated at application startup.

  ### Returns

  * A list of locale ID atoms.

  """
  @spec supported_locales() :: [atom()]
  def supported_locales do
    :persistent_term.get({:localize, :supported_locales}, nil) ||
      Localize.SupplementalData.all_locale_ids()
  end

  @doc """
  Sets the list of supported locales in `:persistent_term`.

  This function does not modify the application configuration.
  It directly updates the runtime cache that `supported_locales/0`
  reads from.

  ### Arguments

  * `locales` is a list of locale ID atoms.

  ### Returns

  * `:ok`.

  ### Examples

      iex> original = Localize.supported_locales()
      iex> Localize.put_supported_locales([:en, :fr, :de])
      :ok
      iex> Localize.put_supported_locales(original)
      :ok

      iex> original = Localize.supported_locales()
      iex> Localize.put_supported_locales([:en, :fr, :de])
      :ok
      iex> Localize.supported_locales()
      [:en, :fr, :de]
      iex> Localize.put_supported_locales(original)
      :ok

  """
  @spec put_supported_locales([atom()]) :: :ok
  def put_supported_locales(locales) when is_list(locales) do
    :persistent_term.put({:localize, :supported_locales}, locales)
    Localize.Locale.Loader.clear_locale_cache()
  end

  @doc """
  Returns a list of all known CLDR locale name atoms.

  ### Returns

  * A list of locale name atoms.

  ### Examples

      iex> locales = Localize.all_locale_ids()
      iex> :en in locales
      true

  """
  @spec all_locale_ids() :: [atom()]
  def all_locale_ids do
    Localize.SupplementalData.all_locale_ids()
  end

  @doc """
  Returns a list of all known CLDR locale ID atoms at or above the
  given coverage level.

  CLDR assigns each locale a coverage level of `:basic`,
  `:moderate`, or `:modern`. A locale at the `:modern` level is
  also included when requesting `:moderate` or `:basic`. A locale
  at `:moderate` is also included when requesting `:basic`.

  ### Arguments

  * `level` is one of `:basic`, `:moderate`, or `:modern`.

  ### Returns

  * A sorted list of locale ID atoms.

  ### Examples

      iex> locales = Localize.all_locale_ids(:modern)
      iex> :en in locales
      true

      iex> length(Localize.all_locale_ids(:basic)) >= length(Localize.all_locale_ids(:modern))
      true

  """
  @spec all_locale_ids(:basic | :moderate | :modern) :: [atom()]
  def all_locale_ids(level) when level in @coverage_levels do
    Localize.SupplementalData.coverage_levels()
    |> Map.fetch!(level)
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

      iex> Localize.available_locale_id?(:en)
      true

      iex> Localize.available_locale_id?(:zzzz)
      false

  """
  @spec available_locale_id?(atom() | String.t()) :: boolean()
  def available_locale_id?(locale_name) when is_atom(locale_name) do
    locale_name in all_locale_ids()
  end

  def available_locale_id?(locale_name) when is_binary(locale_name) do
    available_locale_id?(String.to_atom(locale_name))
  end

  @doc """
  Returns a list of all known CLDR calendar types
  as atoms.

  The calendar types are internal CLDR values to
  identify localized month and day names, era names
  and other calendarical data.

  The calendars defined in the [localzie_calendars](https://hex.pm/packages/localize_calendars)
  embed the appropriate CLDR calendar type to support
  localization.

  ### Returns

  * A list of calendar type atoms.

  ### Examples

      iex> Localize.known_calendars()
      [:gregorian, :buddhist, :chinese, :coptic, :dangi, :ethiopic,
       :ethiopic_amete_alem, :hebrew, :indian, :islamic, :islamic_civil,
       :islamic_rgsa, :islamic_tbla, :islamic_umalqura, :japanese, :persian, :roc]

  """
  @spec known_calendars() :: [atom(), ...]
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
    calendar
    |> normalize_calendar()
    |> validate_calendar()
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

  @doc """
  Returns the list of canonical measurement system atoms.

  The canonical names are derived from `bcp47/measure.xml` and
  mapped to the short forms `:metric`, `:us`, and `:uk`.

  ### Returns

  * A list of measurement system atoms.

  ### Examples

      iex> Localize.measurement_systems()
      [:metric, :uk, :us]

  """
  @spec measurement_systems() :: [atom()]
  def measurement_systems do
    Localize.SupplementalData.measurement_systems()
    |> Map.fetch!(:systems)
    |> Map.keys()
    |> Enum.sort()
  end

  @doc """
  Validates a measurement system type.

  Accepts canonical names (`:metric`, `:us`, `:uk`) as well as
  aliases defined in CLDR (`:imperial`, `:ussystem`, `:uksystem`).
  Aliases are resolved to the canonical short name.

  ### Arguments

  * `system` is a measurement system atom or string.

  ### Returns

  * `{:ok, canonical_atom}` where `canonical_atom` is the
    canonical measurement system atom.

  * `{:error, exception}` if the measurement system is not known.

  ### Examples

      iex> Localize.validate_measurement_system(:metric)
      {:ok, :metric}

      iex> Localize.validate_measurement_system("us")
      {:ok, :us}

      iex> Localize.validate_measurement_system(:imperial)
      {:ok, :uk}

      iex> Localize.validate_measurement_system(:ussystem)
      {:ok, :us}

      iex> Localize.validate_measurement_system(:klingon)
      {:error, %Localize.UnknownMeasurementSystemError{measurement_system: :klingon}}

  """
  @spec validate_measurement_system(atom() | String.t()) ::
          {:ok, atom()} | {:error, Exception.t()}
  def validate_measurement_system(system) when is_binary(system) do
    system
    |> String.downcase()
    |> String.to_existing_atom()
    |> validate_measurement_system()
  rescue
    ArgumentError ->
      {:error, Localize.UnknownMeasurementSystemError.exception(measurement_system: system)}
  end

  def validate_measurement_system(system) when is_atom(system) do
    %{systems: systems, aliases: aliases} = Localize.SupplementalData.measurement_systems()

    cond do
      Map.has_key?(systems, system) ->
        {:ok, system}

      Map.has_key?(aliases, system) ->
        {:ok, Map.fetch!(aliases, system)}

      true ->
        {:error, Localize.UnknownMeasurementSystemError.exception(measurement_system: system)}
    end
  end

  @doc """
  Validates a locale identifier or language tag.

  Ensures that the given locale can be resolved to a known CLDR
  locale. When given a binary locale identifier, it is parsed into
  a `t:Localize.LanguageTag.t/0`. When given an existing language tag
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
    list is all CLDR locale IDs.

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
    case locale_cache_lookup(locale_id) do
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

        locale_cache_store(locale_id, result)
        result
    end
  end

  def validate_locale(locale_id) when is_atom(locale_id) do
    validate_locale(Atom.to_string(locale_id))
  end

  def validate_locale(invalid) do
    {:error, Localize.InvalidLocaleError.exception(locale_id: inspect(invalid))}
  end

  defp locale_cache_lookup(locale_id) do
    cache_key = locale_cache_key(locale_id)

    if :ets.whereis(@locale_cache_table) != :undefined do
      case :ets.lookup(@locale_cache_table, cache_key) do
        [{^cache_key, result}] -> result
        [] -> :miss
      end
    else
      :miss
    end
  end

  defp locale_cache_store(locale_id, {:ok, _tag} = result) do
    cache_key = locale_cache_key(locale_id)

    if :ets.whereis(@locale_cache_table) != :undefined do
      :ets.insert(@locale_cache_table, {cache_key, result})
    end

    :ok
  end

  defp locale_cache_store(_cache_key, {:error, _}) do
    :ok
  end

  defp locale_cache_key(locale_id) do
    locale_id
    |> String.replace("_", "-")
    |> String.downcase()
  end

  # When supported_locales is configured and the tag's cldr_locale_id
  # was already set by LanguageTag.new, check whether it's in the
  # supported list. If not, re-resolve via best_match against the
  # supported list to find the closest supported locale.
  defp resolve_cldr_locale(%Localize.LanguageTag{cldr_locale_id: nil} = language_tag) do
    supported_locale_ids = supported_locales()

    case Localize.LanguageTag.best_match(language_tag, supported_locale_ids) do
      {:ok, cldr_locale_id, _score} ->
        {:ok, %{language_tag | cldr_locale_id: cldr_locale_id}}

      {:error, _} ->
        locale_id = Localize.LanguageTag.to_string(language_tag)
        {:error, Localize.UnknownLocaleError.exception(locale_id: locale_id)}
    end
  end

  defp maybe_restrict_to_supported(%Localize.LanguageTag{cldr_locale_id: cldr_locale_id} = tag) do
    if cldr_locale_id in supported_locales() do
      {:ok, tag}
    else
      resolve_cldr_locale(%{tag | cldr_locale_id: nil})
    end
  end
end
