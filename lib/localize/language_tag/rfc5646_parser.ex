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

  defp unwrap({:ok, acc, "", _, _, _}, input) when is_list(acc) do
    case duplicate_singleton(acc) do
      nil ->
        {:ok, acc}

      singleton ->
        {:error,
         Localize.ParseError.exception(
           input: input,
           reason: :unexpected_input,
           detail:
             "duplicate singleton #{inspect(singleton)} - " <>
               "a singleton subtag must not appear more than once"
         )}
    end
  end

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

  # RFC 5646 section 2.2.6: a singleton subtag must not be repeated
  # within a tag. The grammar surfaces repeats as duplicate `:locale`
  # ("u") or `:transform` ("t") entries, and as `:duplicate_singleton`
  # markers for the generic a-z singletons (recorded by
  # `Localize.Rfc5646.Helpers.do_collapse_extensions/1` when two
  # extension maps collide on the same singleton key).
  defp duplicate_singleton(fields) do
    cond do
      length(Keyword.get_values(fields, :locale)) > 1 -> "u"
      length(Keyword.get_values(fields, :transform)) > 1 -> "t"
      singleton = Keyword.get(fields, :duplicate_singleton) -> singleton
      true -> nil
    end
  end

  # parsec:Localize.Rfc5646.Parser

  # language-tag  = langtag             ; normal language tags
  #               / privateuse          ; private use tag
  #               / grandfathered       ; grandfathered tags

  import NimbleParsec
  import Localize.Rfc5646.Grammar

  # Grandfathered tags are tried first, but only when they span the
  # entire input (the `lookahead(eos())` guard): a grandfathered tag
  # is a complete Language-Tag and cannot carry further subtags. The
  # guard lets inputs that merely share a grandfathered prefix (e.g.
  # "zh-min-nan-x-foo") fall through to the `langtag` production.
  # Trying `langtag` first would wrongly commit to a prefix of the
  # irregular tags ("sgn-be-fr" parses as language "sgn" + region
  # "be", stranding "-fr").
  defparsec(
    :language_tag,
    choice([
      grandfathered() |> lookahead(eos()),
      langtag(),
      private_use()
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
