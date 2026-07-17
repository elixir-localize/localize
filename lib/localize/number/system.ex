defmodule Localize.Number.System do
  @moduledoc """
  Functions to manage number systems for a locale.

  Number systems define different representations for numeric
  values. They are one of two types:

  * Numeric systems use a predefined set of digits to represent
    numbers (e.g., Western digits, Thai digits, Devanagari digits).

  * Algorithmic systems use rules to format numbers and do not
    have a simple digit mapping (e.g., Roman numerals, Chinese
    numerals).

  Each locale defines number system types that map to specific
  number systems:

  * `:default` — the default number system for the locale.

  * `:native` — the number system using the script's native digits.

  * `:traditional` — traditional numerals (may be algorithmic).

  * `:finance` — financial numerals (e.g., anti-fraud ideographs).

  """

  alias Localize.Number.Transliterate
  alias Localize.Utils.Helpers

  @default_number_system_type :default

  @type system_name :: atom()
  @type system_type :: :default | :native | :traditional | :finance

  @known_number_system_types [:default, :native, :traditional, :finance]

  # Lazy-load number systems from ETF at runtime and cache in persistent_term.
  @persistent_term_key {:localize, :number_systems}
  @numeric_systems_key {:localize, :numeric_systems}
  @algorithmic_systems_key {:localize, :algorithmic_systems}

  @doc """
  Returns the default number system type.

  The default number system type is `:default`.

  ### Returns

  * The atom `:default`.

  ### Examples

      iex> Localize.Number.System.default_number_system_type()
      :default

  """
  @spec default_number_system_type() :: :default
  def default_number_system_type do
    @default_number_system_type
  end

  @doc """
  Returns a map of all CLDR number systems and their definitions.

  Each system map contains `:type` (`:numeric` or `:algorithmic`)
  and either `:digits` (for numeric systems) or `:rules` (for
  algorithmic systems).

  ### Returns

  * A map of `%{system_name => system_definition}`.

  ### Examples

      iex> Localize.Number.System.number_systems()[:latn]
      %{type: :numeric, digits: "0123456789"}

  """
  @spec number_systems() :: map()
  def number_systems do
    case :persistent_term.get(@persistent_term_key, :not_loaded) do
      :not_loaded -> load_number_systems()
      systems -> systems
    end
  end

  @doc """
  Returns a map of number systems that have their own digit
  character representations.

  ### Returns

  * A map of `%{system_name => %{type: :numeric, digits: String.t()}}`.

  ### Examples

      iex> Localize.Number.System.numeric_systems()[:thai]
      %{type: :numeric, digits: "๐๑๒๓๔๕๖๗๘๙"}

  """
  @spec numeric_systems() :: map()
  def numeric_systems do
    case :persistent_term.get(@numeric_systems_key, :not_loaded) do
      :not_loaded ->
        load_number_systems()
        :persistent_term.get(@numeric_systems_key)

      systems ->
        systems
    end
  end

  @doc """
  Returns a map of number systems that are algorithmic.

  Algorithmic number systems don't have decimal digits. Numbers
  are formed by algorithm using rules-based number formats.

  ### Returns

  * A map of `%{system_name => %{type: :algorithmic, rules: String.t()}}`.

  ### Examples

      iex> Localize.Number.System.algorithmic_systems()[:roman]
      %{type: :algorithmic, rules: "roman-upper"}

  """
  @spec algorithmic_systems() :: map()
  def algorithmic_systems do
    case :persistent_term.get(@algorithmic_systems_key, :not_loaded) do
      :not_loaded ->
        load_number_systems()
        :persistent_term.get(@algorithmic_systems_key)

      systems ->
        systems
    end
  end

  @doc """
  Returns the list of known number system type names.

  ### Returns

  * A list of atoms: `[:default, :native, :traditional, :finance]`.

  ### Examples

      iex> Localize.Number.System.known_number_system_types()
      [:default, :native, :traditional, :finance]

  """
  @spec known_number_system_types() :: [system_type(), ...]
  def known_number_system_types do
    @known_number_system_types
  end

  @doc """
  Returns the list of known number system names.

  ### Returns

  * A list of atoms representing all known number system names.

  ### Examples

      iex> :latn in Localize.Number.System.known_number_systems()
      true

  """
  @spec known_number_systems() :: [system_name()]
  def known_number_systems do
    Map.keys(number_systems())
  end

  @doc """
  Returns the number system types mapped to number system names
  for a locale.

  ### Arguments

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0` struct.

  ### Returns

  * `{:ok, systems_map}` where `systems_map` is a map like
    `%{default: :latn, native: :latn}`.

  * `{:error, exception}` if the locale data cannot be loaded.

  ### Examples

      iex> Localize.Number.System.number_systems_for(:en)
      {:ok, %{default: :latn, native: :latn}}

  """
  @spec number_systems_for(Localize.LanguageTag.t() | atom() | String.t()) ::
          {:ok, map()} | {:error, Exception.t()}
  def number_systems_for(locale) do
    with {:ok, locale_id} <- cldr_locale_id_from(locale),
         {:ok, raw_systems} <- Localize.Locale.get(locale_id, [:number_systems]) do
      systems =
        raw_systems
        |> Enum.map(fn {key, value} ->
          {to_atom_key(key), to_atom_key(value)}
        end)
        |> Map.new()

      {:ok, systems}
    end
  end

  @doc """
  Same as `number_systems_for/1` but raises on error.

  ### Arguments

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0` struct.

  ### Returns

  * A map of number system types to names.

  ### Raises

  * Raises an exception if the locale data cannot be loaded.

  ### Examples

      iex> Localize.Number.System.number_systems_for!(:en)
      %{default: :latn, native: :latn}

  """
  @spec number_systems_for!(Localize.LanguageTag.t() | atom() | String.t()) :: map()
  def number_systems_for!(locale) do
    case number_systems_for(locale) do
      {:ok, systems} -> systems
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Returns the unique number system names available for a locale.

  ### Arguments

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0` struct.

  ### Returns

  * `{:ok, names}` where `names` is a list of unique
    number system name atoms.

  * `{:error, exception}` if the locale data cannot be loaded.

  ### Examples

      iex> Localize.Number.System.number_system_names_for(:en)
      {:ok, [:latn]}

  """
  @spec number_system_names_for(Localize.LanguageTag.t() | atom() | String.t()) ::
          {:ok, [system_name()]} | {:error, Exception.t()}
  def number_system_names_for(locale) do
    with {:ok, systems} <- number_systems_for(locale) do
      {:ok, systems |> Map.values() |> Enum.uniq()}
    end
  end

  @doc """
  Same as `number_system_names_for/1` but raises on error.

  ### Arguments

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0` struct.

  ### Returns

  * A list of unique number system name atoms.

  ### Raises

  * Raises an exception if the locale data cannot be loaded.

  ### Examples

      iex> Localize.Number.System.number_system_names_for!(:th)
      [:latn, :thai]

  """
  @spec number_system_names_for!(Localize.LanguageTag.t() | atom() | String.t()) ::
          [system_name()]
  def number_system_names_for!(locale) do
    case number_system_names_for(locale) do
      {:ok, names} -> names
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Returns the default number system from a language tag or locale.

  If the language tag has a `-u-nu-` extension, that number system
  is returned. Otherwise, the default number system for the locale
  is returned.

  ### Arguments

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0` struct.

  ### Returns

  * A number system name atom.

  * `{:error, exception}` if the locale data cannot be loaded.

  ### Examples

      iex> Localize.Number.System.number_system_from_locale("en-US")
      {:ok, :latn}

  """
  @spec number_system_from_locale(Localize.LanguageTag.t() | atom() | String.t()) ::
          {:ok, system_name()} | {:error, Exception.t()}
  def number_system_from_locale(%Localize.LanguageTag{locale: %{nu: number_system}})
      when not is_nil(number_system) do
    {:ok, number_system}
  end

  def number_system_from_locale(%Localize.LanguageTag{} = locale) do
    with {:ok, validated} <- Localize.validate_locale(locale),
         {:ok, systems} <- number_systems_for(validated) do
      {:ok, Map.fetch!(systems, @default_number_system_type)}
    end
  end

  def number_system_from_locale(locale) when is_binary(locale) or is_atom(locale) do
    with {:ok, language_tag} <- Localize.validate_locale(locale) do
      number_system_from_locale(language_tag)
    end
  end

  @doc """
  Resolves a number system name from a system type or direct name
  for a locale.

  Number systems can be referenced by type (`:default`, `:native`,
  etc.) or directly by name (`:latn`, `:arab`, etc.). This function
  resolves the reference to the actual system name.

  Following TR35 and ICU, any numbering system in the CLDR inventory
  is accepted by name even when the locale does not list it — the
  `-u-nu-` locale keyword and the `:number_system` formatting option
  may request, for example, `:thai` digits in an `:en` locale. Only
  genuinely unknown system names return an error.

  ### Arguments

  * `system_name` is a number system name atom or type atom.

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0` struct.

  ### Returns

  * `{:ok, system_name}` where `system_name` is an atom.

  * `{:error, exception}` if the system name cannot be resolved.

  ### Examples

      iex> Localize.Number.System.system_name_from(:default, :en)
      {:ok, :latn}

      iex> Localize.Number.System.system_name_from(:thai, :th)
      {:ok, :thai}

      iex> Localize.Number.System.system_name_from(:thai, :en)
      {:ok, :thai}

  """
  @spec system_name_from(
          system_name() | system_type(),
          Localize.LanguageTag.t() | atom() | String.t()
        ) ::
          {:ok, system_name()} | {:error, Exception.t()}
  def system_name_from(system_name, locale) do
    system_name = to_atom_key(system_name)

    with {:ok, locale_id} <- cldr_locale_id_from(locale),
         {:ok, number_systems} <- number_systems_for(locale_id) do
      cond do
        # It's a type (default, native, etc.) — resolve to actual system name
        Map.has_key?(number_systems, system_name) ->
          {:ok, Map.get(number_systems, system_name)}

        # It's already a direct system name for this locale
        system_name in Map.values(number_systems) ->
          {:ok, system_name}

        # Known globally even though the locale does not list it.
        # Per TR35/ICU an explicit numbering-system request (the
        # `-u-nu-` keyword or a direct option) is honoured for any
        # CLDR numbering system: formats and symbols inherit from
        # the locale's default system (root aliases them to `latn`)
        # while digits come from the requested system.
        Map.has_key?(number_systems(), system_name) ->
          {:ok, system_name}

        true ->
          {:error, Localize.UnknownNumberSystemError.exception(number_system: system_name)}
      end
    end
  end

  @doc """
  Same as `system_name_from/2` but raises on error.

  ### Arguments

  * `system_name` is a number system name atom or type atom.

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0` struct.

  ### Returns

  * A number system name atom.

  ### Raises

  * Raises an exception if the system name cannot be resolved.

  ### Examples

      iex> Localize.Number.System.system_name_from!(:native, :ar)
      :arab

  """
  @spec system_name_from!(
          system_name() | system_type(),
          Localize.LanguageTag.t() | atom() | String.t()
        ) ::
          system_name()
  def system_name_from!(system_name, locale) do
    case system_name_from(system_name, locale) do
      {:ok, name} -> name
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Returns the actual number system definition from a system name
  and locale.

  Resolves a system type or name to the full system definition
  containing `:type` and `:digits` or `:rules`.

  ### Arguments

  * `locale` is a locale identifier atom, string, or a
    `t:Localize.LanguageTag.t/0` struct.

  * `system_name` is a number system name or type atom.

  ### Returns

  * `{:ok, system_definition}` with the system's type and digits/rules.

  * `{:error, exception}` if the system cannot be resolved.

  ### Examples

      iex> Localize.Number.System.number_system_for(:en, :default)
      {:ok, %{type: :numeric, digits: "0123456789"}}

      iex> Localize.Number.System.number_system_for(:th, :thai)
      {:ok, %{type: :numeric, digits: "๐๑๒๓๔๕๖๗๘๙"}}

  """
  @spec number_system_for(
          Localize.LanguageTag.t() | atom() | String.t(),
          system_name() | system_type()
        ) ::
          {:ok, map()} | {:error, Exception.t()}
  def number_system_for(locale, system_name) do
    with {:ok, resolved_name} <- system_name_from(system_name, locale) do
      case Map.get(number_systems(), resolved_name) do
        nil ->
          {:error,
           Localize.InvalidValueError.exception(
             value: system_name,
             expected: "a known number system",
             context: "Localize.Number.System.number_system_for/2"
           )}

        definition ->
          {:ok, definition}
      end
    end
  end

  @doc """
  Returns the digit string for a numeric number system.

  ### Arguments

  * `system_name` is a number system name atom (e.g., `:latn`).

  ### Returns

  * `{:ok, digits}` where `digits` is a 10-character string.

  * `{:error, exception}` if the system is not numeric or unknown.

  ### Examples

      iex> Localize.Number.System.number_system_digits(:latn)
      {:ok, "0123456789"}

  """
  @spec number_system_digits(system_name()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def number_system_digits(system_name) do
    system_name = to_atom_key(system_name)

    case Map.get(numeric_systems(), system_name) do
      nil ->
        {:error,
         Localize.InvalidValueError.exception(
           value: system_name,
           expected: "a numeric number system with digits",
           context: "Localize.Number.System.number_system_digits/1"
         )}

      system ->
        {:ok, Map.get(system, :digits)}
    end
  end

  @doc """
  Same as `number_system_digits/1` but raises on error.

  ### Arguments

  * `system_name` is a number system name atom.

  ### Returns

  * A string of the number system's digits.

  ### Raises

  * Raises an exception if the system is not numeric or unknown.

  ### Examples

      iex> Localize.Number.System.number_system_digits!(:latn)
      "0123456789"

  """
  @spec number_system_digits!(system_name()) :: String.t()
  def number_system_digits!(system_name) do
    case number_system_digits(system_name) do
      {:ok, digits} -> digits
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Converts a number into the representation of a non-Latin
  number system.

  For numeric systems, transliterates the digits. For algorithmic
  systems, formats the number using the system's RBNF rules.

  ### Arguments

  * `number` is an integer, float, or Decimal.

  * `system_name` is a number system name atom.

  ### Returns

  * `{:ok, string}` with the number in the requested number system.

  * `{:error, exception}` if the system is unknown.

  ### Examples

      iex> Localize.Number.System.to_system(123, :thai)
      {:ok, "๑๒๓"}

      iex> Localize.Number.System.to_system(1234, :roman)
      {:ok, "MCCXXXIV"}

  """
  @spec to_system(number() | Decimal.t(), system_name()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def to_system(number, system_name) do
    system_name = to_atom_key(system_name)

    case Map.get(number_systems(), system_name) do
      nil ->
        {:error,
         Localize.InvalidValueError.exception(
           value: system_name,
           expected: "a known number system",
           context: "Localize.Number.System.to_system/2"
         )}

      %{type: :numeric, digits: digits} ->
        {:ok, latn_digits} = number_system_digits(:latn)
        number_string = to_string(number)
        transliteration_map = generate_transliteration_map(latn_digits, digits)
        {:ok, Transliterate.transliterate_digits(number_string, transliteration_map)}

      %{type: :algorithmic, rules: rules} ->
        # Delegate to RBNF processor
        # Rules can be "rule_name" or "locale/group/rule_name"
        {rbnf_locale, rule_name} = parse_rbnf_rule_ref(rules)
        Localize.Number.Rbnf.to_string(number, rule_name, locale: rbnf_locale)
    end
  end

  @doc """
  Same as `to_system/2` but raises on error.

  ### Arguments

  * `number` is an integer, float, or Decimal.

  * `system_name` is a number system name atom.

  ### Returns

  * A string with the number in the requested number system.

  ### Raises

  * Raises an exception if the system is unknown.

  ### Examples

      iex> Localize.Number.System.to_system!(123, :deva)
      "१२३"

  """
  @spec to_system!(number() | Decimal.t(), system_name()) :: String.t()
  def to_system!(number, system_name) do
    case to_system(number, system_name) do
      {:ok, string} -> string
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Generates a transliteration map between two digit strings.

  ### Arguments

  * `from` is a string of digits to map from.

  * `to` is a string of digits to map to (must be same length).

  ### Returns

  * A map of `%{grapheme => grapheme}`.

  * `{:error, exception}` if the strings are not the same length.

  ### Examples

      iex> Localize.Number.System.generate_transliteration_map("0123456789", "9876543210")
      %{
        "0" => "9",
        "1" => "8",
        "2" => "7",
        "3" => "6",
        "4" => "5",
        "5" => "4",
        "6" => "3",
        "7" => "2",
        "8" => "1",
        "9" => "0"
      }

  """
  @spec generate_transliteration_map(String.t(), String.t()) ::
          map() | {:error, Exception.t()}
  def generate_transliteration_map(from, to) when is_binary(from) and is_binary(to) do
    if String.length(from) == String.length(to) do
      from
      |> String.graphemes()
      |> Enum.zip(String.graphemes(to))
      |> Map.new()
    else
      {:error,
       Localize.InvalidValueError.exception(
         value: {from, to},
         expected: "two strings of the same length",
         context: "Localize.Number.System.generate_transliteration_map/2"
       )}
    end
  end

  # ── Private helpers ──────────────────────────────────────────

  # Resolve the ETF path at runtime. Storing `Application.app_dir/2` in a
  # module attribute bakes the build host's absolute path into the BEAM,
  # which then fails to read on the target host of a Mix release built on
  # a different machine (e.g. CI runner -> production VM).
  defp number_systems_path do
    Application.app_dir(:localize, "priv/localize/supplemental_data/number_systems.etf")
  end

  defp load_number_systems do
    Localize.DataLoader.load(@persistent_term_key, fn ->
      systems = number_systems_path() |> File.read!() |> :erlang.binary_to_term()

      numeric =
        systems
        |> Enum.reject(fn {_name, system} -> is_nil(system[:digits]) end)
        |> Map.new()

      algorithmic =
        systems
        |> Enum.filter(fn {_name, system} -> system.type == :algorithmic end)
        |> Map.new()

      :persistent_term.put(@numeric_systems_key, numeric)
      :persistent_term.put(@algorithmic_systems_key, algorithmic)

      systems
    end)
  end

  defp cldr_locale_id_from(locale), do: Localize.Locale.cldr_locale_id_from(locale)

  defp to_atom_key(key) when is_atom(key), do: key
  # Use `existing_atom/1` so attacker-supplied binary system names
  # can't grow the atom table. Known number-system names and types
  # are pre-atomised at startup (see `@known_number_system_types` and
  # `known_number_systems/0`), so this lookup succeeds for legitimate
  # input. Unknown binaries return nil; downstream callers' `Map.get`
  # / `Map.has_key?` checks fall through to the existing error paths.
  defp to_atom_key(key) when is_binary(key), do: Helpers.existing_atom(key)

  # Parse RBNF rule reference from algorithmic number system definition.
  # Can be "rule_name" or "locale/RuleGroup/rule_name"
  defp parse_rbnf_rule_ref(rules) when is_binary(rules) do
    case String.split(rules, "/") do
      [rule_name] ->
        # Simple rule name — look in root locale (und)
        {:und, rule_name}

      [locale, _group, rule_name] ->
        # locale/RuleGroup/rule_name
        locale_atom = String.to_atom(locale)
        # Convert camelCase rule name to snake_case with underscores
        normalized = rule_name |> String.replace("-", "_")
        {locale_atom, normalized}

      _ ->
        {:und, rules}
    end
  end
end
