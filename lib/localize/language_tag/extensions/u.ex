defmodule Localize.LanguageTag.U do
  @moduledoc """
  Defines the struct for the BCP 47 `u` extension and provides a
  standalone parser for `-u-` extension strings.

  The `u` extension carries Unicode locale keywords such as the
  calendar (`ca`), hour cycle (`hc`), numbering system (`nu`) and
  collation options (`co`, `ks`, …). It is normally populated on a
  `t:Localize.LanguageTag.t/0` by `Localize.validate_locale/1`;
  `parse/1` parses an extension string on its own, for consumers
  that receive the `-u-` subtags without a full locale identifier.

  """

  @fields Localize.Validity.U.Fields.fields()

  typespec =
    {:%, [],
     [
       {:__MODULE__, [], Localize.LanguageTag.U},
       {:%{}, [], Enum.map(@fields, fn f -> {f, {:atom, [], []}} end)}
     ]}

  defstruct @fields

  @typedoc """
  Defines the [BCP 47 `u` extension](https://unicode-org.github.io/cldr/ldml/tr35.html#u_Extension)
  of a `t:Localize.LanguageTag`.

  """
  @type t :: unquote(typespec)

  @doc """
  Parses a standalone BCP 47 `u` extension string.

  The keywords are validated and canonicalized exactly as they
  would be by `Localize.validate_locale/1` on a full locale
  identifier: keys are checked against the CLDR validity data,
  aliases are resolved, and values are decoded to their canonical
  atoms (e.g. `ca-gregory` decodes to `:gregorian`).

  ### Arguments

  * `u_extension` is the extension subtags as a string, with or
    without the leading `u-` singleton (e.g. `"ca-gregory-hc-h23"`
    or `"u-ca-gregory-hc-h23"`).

  ### Returns

  * `{:ok, u}` where `u` is a `t:t/0` struct with the decoded
    keywords set.

  * `{:error, exception}` if the extension string cannot be parsed
    or a keyword fails validation.

  ### Examples

      iex> {:ok, u} = Localize.LanguageTag.U.parse("ca-gregory-hc-h23")
      iex> {u.ca, u.hc}
      {:gregorian, :h23}

      iex> {:ok, u} = Localize.LanguageTag.U.parse("u-nu-thai")
      iex> u.nu
      :thai

      iex> {:error, _} = Localize.LanguageTag.U.parse("not a u extension")

  """
  @spec parse(String.t()) :: {:ok, t()} | {:error, Exception.t()}
  def parse(u_extension) when is_binary(u_extension) do
    subtags =
      u_extension
      |> String.trim()
      |> String.trim_leading("-")
      |> String.replace_prefix("u-", "")

    with {:ok, language_tag} <- Localize.LanguageTag.parse("und-u-" <> subtags),
         {:ok, canonical} <- Localize.LanguageTag.canonicalize(language_tag) do
      case canonical.locale do
        %__MODULE__{} = u -> {:ok, u}
        _other -> {:ok, struct(__MODULE__)}
      end
    end
  end

  @doc """
  Same as `parse/1` but raises on error.

  ### Arguments

  * `u_extension` is the string content of a `-u-` extension.

  ### Returns

  * A `t:Localize.LanguageTag.U.t/0` struct.

  ### Raises

  * Raises an exception if the extension cannot be parsed.

  ### Examples

      iex> u = Localize.LanguageTag.U.parse!("ca-iso8601")
      iex> u.ca
      :iso8601

  """
  @spec parse!(String.t()) :: t()
  def parse!(u_extension) do
    case parse(u_extension) do
      {:ok, u} -> u
      {:error, exception} -> raise exception
    end
  end

  @doc false
  def canonicalize_locale_keys(%Localize.LanguageTag{locale: locale} = language_tag)
      when locale == %{} do
    {:ok, language_tag}
  end

  def canonicalize_locale_keys(%Localize.LanguageTag{locale: locale} = language_tag) do
    with {:ok, locale} <- validate_keys(locale) do
      {:ok, Map.put(language_tag, :locale, struct(__MODULE__, locale))}
    end
  end

  # Standalone attributes are not supported
  # in this implementation and they are ignored
  defp validate_keys(locale) do
    Enum.reduce_while(locale, {:ok, %{}}, fn
      {:attributes, _value}, {:ok, acc} ->
        {:cont, {:ok, acc}}

      {key, value}, {:ok, acc} ->
        case Localize.Validity.U.decode(key, value) do
          {:ok, {key, value}} -> {:cont, {:ok, Map.put(acc, key, value)}}
          other -> {:halt, other}
        end
    end)
  end

  @doc """
  Encodes a `t:t/0` struct as canonical BCP 47 key/value pairs.

  ### Arguments

  * `u_extension` is a `t:t/0` struct.

  ### Returns

  * A list of `{key, value}` string tuples sorted by key, using the
    canonical BCP 47 forms (e.g. `:gregorian` encodes as
    `{"ca", "gregory"}`).

  ### Examples

      iex> {:ok, u} = Localize.LanguageTag.U.parse("hc-h23-ca-gregory")
      iex> Localize.LanguageTag.U.encode(u)
      [{"ca", "gregory"}, {"hc", "h23"}]

  """
  @spec encode(t()) :: [{String.t(), String.t()}]
  def encode(%__MODULE__{} = u_extension) do
    for field <- @fields, value = Map.get(u_extension, field), !is_nil(value) do
      Localize.Validity.U.encode(field, value)
    end
    |> Enum.sort()
  end

  @doc false
  def to_string(%__MODULE__{} = u_extension) do
    u_extension
    |> encode()
    |> Enum.map_join("-", fn {k, v} -> "#{k}-#{v}" end)
  end

  @doc false
  def to_string(locale) when locale == %{} do
    ""
  end

  defimpl String.Chars do
    def to_string(locale) do
      Localize.LanguageTag.U.to_string(locale)
    end
  end

  defimpl Localize.LanguageTag.Chars do
    def to_string(locale) do
      Localize.LanguageTag.U.to_string(locale)
    end
  end
end
