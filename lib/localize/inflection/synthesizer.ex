defmodule Localize.Inflection.Synthesizer do
  @moduledoc false

  # Behaviour for per-language grammar synthesizers.
  #
  # A synthesizer provides the default feature functions (number,
  # gender, definiteness, articles, …) and the display function that
  # applies constraints to a phrase, mirroring the upstream
  # `XxGrammarSynthesizer` classes.

  alias Localize.Inflection.DisplayValue

  @typedoc "A map of feature name to constraint value."
  @type constraints :: %{optional(binary) => binary}

  @doc """
  Computes the value of `feature` for a display value, or nil when
  the feature has no default function or no determinable value.
  """
  @callback feature_value(
              feature :: binary,
              display_value :: DisplayValue.t(),
              constraints :: constraints
            ) :: Localize.Inflection.SpeakableString.t() | nil

  @doc """
  Applies constraints to the best display value, returning nil when
  the constraints cannot be satisfied (and guessing is disabled).
  """
  @callback display_value(
              display_data :: [DisplayValue.t()],
              constraints :: constraints,
              guess? :: boolean
            ) :: DisplayValue.t() | nil

  @synthesizers %{
    en: Localize.Inflection.Synthesizer.En,
    es: Localize.Inflection.Synthesizer.Es,
    fr: Localize.Inflection.Synthesizer.Fr,
    de: Localize.Inflection.Synthesizer.De,
    pt: Localize.Inflection.Synthesizer.Pt,
    it: Localize.Inflection.Synthesizer.It,
    nl: Localize.Inflection.Synthesizer.Nl,
    da: Localize.Inflection.Synthesizer.Da,
    sv: Localize.Inflection.Synthesizer.Sv,
    nb: Localize.Inflection.Synthesizer.Nb,
    uk: Localize.Inflection.Synthesizer.Uk,
    cs: Localize.Inflection.Synthesizer.Cs,
    ru: Localize.Inflection.Synthesizer.Ru,
    pl: Localize.Inflection.Synthesizer.Pl,
    sr: Localize.Inflection.Synthesizer.Sr,
    ro: Localize.Inflection.Synthesizer.Ro,
    he: Localize.Inflection.Synthesizer.He,
    tr: Localize.Inflection.Synthesizer.Tr,
    fi: Localize.Inflection.Synthesizer.Fi,
    ar: Localize.Inflection.Synthesizer.Ar,
    ur: Localize.Inflection.Synthesizer.Ur,
    gu: Localize.Inflection.Synthesizer.Gu,
    hi: Localize.Inflection.Synthesizer.Hi,
    ko: Localize.Inflection.Synthesizer.Ko,
    ml: Localize.Inflection.Synthesizer.Ml,
    kn: Localize.Inflection.Synthesizer.Kn,
    mr: Localize.Inflection.Synthesizer.Mr,
    pa: Localize.Inflection.Synthesizer.Pa,
    te: Localize.Inflection.Synthesizer.Te,
    bn: Localize.Inflection.Synthesizer.Bn,
    ta: Localize.Inflection.Synthesizer.Ta
  }

  @doc """
  Returns the synthesizer module for a locale, or nil.

  """
  def for_locale(locale) do
    Map.get(@synthesizers, locale)
  end
end
