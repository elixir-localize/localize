defmodule Localize.Inflection.Articles do
  @moduledoc false

  # Shared article machinery: building article prefixes with the
  # speak channel preserved, detecting definiteness from a leading
  # article, and applying a definiteness constraint by swapping or
  # prepending articles. Ports of the upstream
  # `DefaultArticleLookupFunction`, `ArticleDetectionFunction` and
  # `DefinitenessDisplayFunction`.

  alias Localize.Inflection.{Data, DisplayValue, SpeakableString}

  @speak "speak"

  @doc """
  Builds the article result for a feature lookup.

  With `include?` false the result is the article alone. Otherwise
  the article is prepended to the display string (with a space when
  `space?` and both sides are non-empty), preserving the speak
  channel.

  """
  def create_preposition(display_value, article, include?, space? \\ true)

  def create_preposition(_display_value, article, false, _space?) do
    article
  end

  def create_preposition(display_value, article, true, space?) do
    display_string = display_value.display_string
    speakable = SpeakableString.new(display_string, speak_value(display_value))

    if space? and display_string != "" and SpeakableString.print(article) != "" do
      article
      |> SpeakableString.concat(" ")
      |> SpeakableString.concat(speakable)
    else
      SpeakableString.concat(article, speakable)
    end
  end

  defp speak_value(display_value) do
    Map.get(display_value.constraints, @speak) || display_value.display_string
  end

  @doc """
  Returns the article prefix set for the named display features:
  every non-empty, non-excluded value with a trailing space
  appended (unless some value of the feature already has one).

  """
  def article_prefixes(locale, feature_names, excluded \\ []) do
    features = Data.metadata!(locale).features.features

    Enum.flat_map(feature_names, fn name ->
      values = get_in(features, [name, :values]) || []
      trailing_space? = Enum.any?(values, &String.ends_with?(&1, " "))

      values
      |> Enum.reject(&(&1 == "" or &1 in excluded))
      |> Enum.map(&if trailing_space?, do: &1, else: &1 <> " ")
    end)
  end

  @doc """
  Detects whether a display string already carries a definite or
  indefinite article, returning "definite", "indefinite" or nil.

  """
  def detect_definiteness(locale, display_value, definite_prefixes, indefinite_prefixes) do
    display_string = display_value.display_string

    if String.length(display_string) < 2 do
      nil
    else
      lowercased = String.downcase(display_string)

      # When any article uses the typographic apostrophe, an ASCII
      # apostrophe in the input is normalized before matching.
      lowercased =
        if Enum.any?(definite_prefixes ++ indefinite_prefixes, &String.contains?(&1, "’")) do
          String.replace(lowercased, "'", "’", global: false)
        else
          lowercased
        end

      definite? = Enum.any?(definite_prefixes, &String.starts_with?(lowercased, &1))
      indefinite? = Enum.any?(indefinite_prefixes, &String.starts_with?(lowercased, &1))
      _ = locale

      cond do
        definite? and not indefinite? -> "definite"
        indefinite? and not definite? -> "indefinite"
        true -> nil
      end
    end
  end

  @doc """
  Applies a definiteness constraint to a display value.

  `definite_fn` and `indefinite_fn` build the article-prefixed
  speakable string for a display value (they receive the stripped
  display value and the constraints).

  """
  def add_definiteness(
        display_value,
        constraints,
        definite_prefixes,
        indefinite_prefixes,
        definite_fn,
        indefinite_fn
      ) do
    case Map.get(constraints, "definiteness") do
      nil ->
        display_value

      definiteness ->
        definite_length = article_prefix_length(display_value, definite_prefixes)

        indefinite_length =
          if definite_length <= 0 do
            article_prefix_length(display_value, indefinite_prefixes)
          else
            0
          end

        stripped =
          strip_prefix(display_value.display_string, max(definite_length, indefinite_length))

        base = %DisplayValue{display_string: stripped, constraints: display_value.constraints}

        cond do
          definite_length <= 0 and definiteness == "definite" ->
            apply_article(display_value, base, constraints, definite_fn)

          indefinite_length <= 0 and definiteness == "indefinite" ->
            apply_article(display_value, base, constraints, indefinite_fn)

          true ->
            display_value
        end
    end
  end

  @doc """
  Applies a definiteness constraint, or — when none is present —
  re-derives an existing leading article so it agrees with the
  (possibly re-inflected) phrase.

  """
  def update_definiteness(
        display_value,
        constraints,
        definite_prefixes,
        indefinite_prefixes,
        definite_fn,
        indefinite_fn
      ) do
    if Map.has_key?(constraints, "definiteness") do
      add_definiteness(
        display_value,
        constraints,
        definite_prefixes,
        indefinite_prefixes,
        definite_fn,
        indefinite_fn
      )
    else
      definite_length = article_prefix_length(display_value, definite_prefixes)

      {length, article_fn} =
        if definite_length > 0 do
          {definite_length, definite_fn}
        else
          {article_prefix_length(display_value, indefinite_prefixes), indefinite_fn}
        end

      if length > 0 do
        stripped = strip_prefix(display_value.display_string, length)
        base = %DisplayValue{display_string: stripped, constraints: display_value.constraints}
        apply_article(display_value, base, constraints, article_fn)
      else
        display_value
      end
    end
  end

  defp apply_article(original, base, constraints, article_fn) do
    case article_fn.(base, constraints) do
      nil -> original
      speakable -> DisplayValue.replace(%{original | constraints: base.constraints}, speakable)
    end
  end

  defp article_prefix_length(display_value, prefixes) do
    lowercased = String.downcase(display_value.display_string)

    Enum.find_value(prefixes, -1, fn prefix ->
      if byte_size(prefix) < byte_size(lowercased) and String.starts_with?(lowercased, prefix) do
        byte_size(prefix)
      end
    end)
  end

  defp strip_prefix(display_string, length) when length > 0 do
    binary_part(display_string, length, byte_size(display_string) - length)
  end

  defp strip_prefix(display_string, _length), do: display_string
end
