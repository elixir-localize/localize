defmodule Localize.ContextTransform do
  @moduledoc """
  Cases a name for the context it stands in, as CLDR's context transforms say.

  CLDR writes a name as it appears in the middle of a sentence. French writes language names in lower case, "français", and a menu of languages capitalizes them: "Français". CLDR records, for each locale, which kinds of name change case in which contexts, and `transform/4` applies that record.

  ### Usages

  The kind of name, as CLDR names it: `:languages`, `:script`, `:key_value`, `:calendar_field`, `:currency_name`, `:day_format_except_narrow`, `:day_standalone_except_narrow`, `:month_format_except_narrow`, `:month_standalone_except_narrow`, `:era_abbr`, `:era_name`, `:number_spellout`, `:relative` and `:typographic_names`.

  ### Contexts

  * `:middle_of_sentence` leaves the name as CLDR writes it.

  * `:begin_sentence` titlecases its first word, in every locale.

  * `:ui_list_or_menu` is a name in a menu or a list, such as a language picker. Its case is the locale's.

  * `:stand_alone` is a name that stands by itself, such as a month in a calendar header. Its case is the locale's.

  Titlecasing changes the first letter of the first word and nothing else, so "español (México)" becomes "Español (México)". It follows the language's casing: Turkish and Azerbaijani titlecase "i" as "İ", and Dutch "ij" as "IJ".

  """

  alias Localize.InvalidValueError

  @usages [
    :languages,
    :script,
    :key_value,
    :calendar_field,
    :currency_name,
    :day_format_except_narrow,
    :day_standalone_except_narrow,
    :month_format_except_narrow,
    :month_standalone_except_narrow,
    :era_abbr,
    :era_name,
    :number_spellout,
    :relative,
    :typographic_names
  ]

  @contexts [:middle_of_sentence, :begin_sentence, :ui_list_or_menu, :stand_alone]

  # Languages whose casing of "i" is Turkic: "i" titlecases to "İ".
  @turkic_languages [:tr, :az]

  # The leading non-letters, the first letter's grapheme, and the rest.
  @first_letter ~r/\A(\P{L}*)(\X)(.*)\z/su

  @typedoc "A kind of name a context transform applies to."
  @type usage ::
          :languages
          | :script
          | :key_value
          | :calendar_field
          | :currency_name
          | :day_format_except_narrow
          | :day_standalone_except_narrow
          | :month_format_except_narrow
          | :month_standalone_except_narrow
          | :era_abbr
          | :era_name
          | :number_spellout
          | :relative
          | :typographic_names

  @typedoc "A context a name stands in."
  @type context :: :middle_of_sentence | :begin_sentence | :ui_list_or_menu | :stand_alone

  @doc """
  Returns the usages a context transform applies to.

  ### Returns

  * A list of usage atoms.

  ### Examples

      iex> :languages in Localize.ContextTransform.usages()
      true

  """
  @spec usages() :: [usage(), ...]
  def usages do
    @usages
  end

  @doc """
  Returns the contexts a name may stand in.

  ### Returns

  * A list of context atoms.

  ### Examples

      iex> Localize.ContextTransform.contexts()
      [:middle_of_sentence, :begin_sentence, :ui_list_or_menu, :stand_alone]

  """
  @spec contexts() :: [context(), ...]
  def contexts do
    @contexts
  end

  @doc """
  Cases a name for the context it stands in.

  ### Arguments

  * `name` is the name as CLDR writes it, a string.

  * `usage` is the kind of name; see "Usages" in the module documentation.

  * `context` is the context it stands in; see "Contexts" in the module documentation.

  * `options` is a keyword list of options.

  ### Options

  * `:locale` is the locale the name is written in. The default is `Localize.get_locale/0`.

  ### Returns

  * `{:ok, name}` cased for the context, or

  * `{:error, exception}` when `name` is not a string, `usage` or `context` is not one listed above, or `:locale` is not a valid locale.

  ### Examples

      iex> Localize.ContextTransform.transform("français", :languages, :ui_list_or_menu, locale: :fr)
      {:ok, "Français"}

      iex> Localize.ContextTransform.transform("français", :languages, :middle_of_sentence, locale: :fr)
      {:ok, "français"}

      iex> Localize.ContextTransform.transform("janvier", :month_standalone_except_narrow, :stand_alone, locale: :fr)
      {:ok, "Janvier"}

  """
  @spec transform(String.t(), usage(), context(), Keyword.t()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def transform(name, usage, context, options \\ [])

  def transform(name, usage, context, options) when is_binary(name) and is_list(options) do
    with :ok <- validate(usage, @usages, :usage),
         :ok <- validate(context, @contexts, :context),
         {:ok, locale} <-
           Localize.validate_locale(Keyword.get(options, :locale, Localize.get_locale())) do
      {:ok, apply_transform(transform_for(locale, usage, context), name, locale.language)}
    end
  end

  def transform(name, _usage, _context, options) when is_list(options) do
    {:error, InvalidValueError.exception(value: name, expected: "a string")}
  end

  def transform(_name, _usage, _context, options) do
    {:error, Localize.Utils.Helpers.invalid_options(options)}
  end

  @doc false
  # Applies the `:capitalization` option of a display function to its
  # result: the name in `{:ok, name}` is cased for that context in
  # `locale`, the locale it is written in. An error passes through.
  @spec capitalize({:ok, String.t()} | {:error, Exception.t()}, usage(), Keyword.t(), term()) ::
          {:ok, String.t()} | {:error, Exception.t()}
  def capitalize({:ok, name}, usage, options, locale) when is_binary(name) do
    case Keyword.get(options, :capitalization, :middle_of_sentence) do
      :middle_of_sentence -> {:ok, name}
      context -> transform(name, usage, context, locale: locale)
    end
  end

  def capitalize(result, _usage, _options, _locale) do
    result
  end

  defp validate(value, allowed, expected) do
    if value in allowed do
      :ok
    else
      {:error,
       InvalidValueError.exception(value: value, expected: expected, allowed_values: allowed)}
    end
  end

  defp transform_for(_locale, _usage, :middle_of_sentence) do
    :no_change
  end

  defp transform_for(_locale, _usage, :begin_sentence) do
    :titlecase_firstword
  end

  defp transform_for(locale, usage, context) do
    transforms = Localize.SupplementalData.context_transforms()
    get_in(transforms, [locale.cldr_locale_id, usage, context]) || :no_change
  end

  defp apply_transform(:no_change, name, _language) do
    name
  end

  defp apply_transform(:titlecase_firstword, name, language) do
    case Regex.run(@first_letter, name, capture: :all_but_first) do
      [prefix, first, rest] -> prefix <> titlecase(first, rest, language)
      nil -> name
    end
  end

  # Dutch titlecases the digraph "ij" as one letter.
  defp titlecase("i", "j" <> rest, :nl) do
    "IJ" <> rest
  end

  defp titlecase(first, rest, language) when language in @turkic_languages do
    String.capitalize(first, :turkic) <> rest
  end

  defp titlecase(first, rest, _language) do
    String.capitalize(first) <> rest
  end
end
