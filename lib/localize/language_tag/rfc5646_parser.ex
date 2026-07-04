defmodule Localize.Rfc5646.Parser do
  # Implements parsing for [RFC5646](https://datatracker.ietf.org/doc/html/rfc5646) language
  # tags with [BCP47](https://tools.ietf.org/search/bcp47) extensions.
  #
  # The primary interface to this module is the function
  # `Localize.LanguageTag.parse/1`.
  #
  @moduledoc false

  import Localize.Rfc5646.Helpers

  def parse(rule \\ :language_tag, input) when is_atom(rule) and is_binary(input) do
    apply(__MODULE__, rule, [input])
    |> unwrap(input)
  end

  defp unwrap({:ok, acc, "", _, _, _}, _input) when is_list(acc),
    do: {:ok, acc}

  defp unwrap({:error, detail, rest, _, _, offset}, input) do
    {:error,
     Localize.ParseError.exception(
       input: input,
       reason: :unexpected_input,
       detail: detail,
       offset: offset,
       rest: rest
     )}
  end

  # parsec:Localize.Rfc5646.Parser

  # language-tag  = langtag             ; normal language tags
  #               / privateuse          ; private use tag
  #               / grandfathered       ; grandfathered tags

  import NimbleParsec
  import Localize.Rfc5646.Grammar

  defparsec(
    :language_tag,
    choice([
      langtag(),
      private_use(),
      grandfathered()
    ])
    |> eos()
    |> label("a BCP47 language tag")
  )

  # parsec:Localize.Rfc5646.Parser

  def error_on_remaining("", context, _line, _offset) do
    {[], context}
  end

  def error_on_remaining(_rest, _context, _line, _offset) do
    {:error, "invalid language tag"}
  end
end
