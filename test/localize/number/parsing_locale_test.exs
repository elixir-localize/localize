defmodule Localize.Number.ParsingLocaleTest do
  # The test puts fallback data in place of a locale's own, which every
  # process sees, so it runs alone.
  use ExUnit.Case, async: false

  alias Localize.Locale.Provider.PersistentTerm
  alias Localize.Number.Parser

  # A locale no other test reads, given English data as the loader gives it
  # when the locale is not installed and cannot be downloaded.
  @locale :"en-MT"

  setup do
    {:ok, english} = PersistentTerm.load(:en)
    :ok = PersistentTerm.store(@locale, Map.put(english, :name, :en))

    on_exit(fn ->
      case PersistentTerm.load(@locale) do
        {:ok, own} -> PersistentTerm.store(@locale, Map.put(own, :name, @locale))
        {:error, _not_installed} -> :ok
      end
    end)
  end

  # With English data, "$5" would be US dollars wherever the locale is.
  test "parsing refuses a locale whose own data is not installed" do
    for result <- [
          Parser.parse_currency_amount("$5", locale: @locale),
          Parser.parse("1,234.5", locale: @locale),
          Parser.scan("5 apples", locale: @locale),
          Parser.resolve_currency("$", locale: @locale),
          Parser.resolve_per("per", locale: @locale)
        ] do
      assert {:error, %Localize.LocaleNotFoundInCacheError{locale_id: @locale}} = result
    end
  end

  test "the refusal says how to install the locale" do
    assert {:error, error} = Parser.parse_currency_amount("$5", locale: @locale)
    assert Exception.message(error) =~ "mix localize.download_locales en-MT"
  end

  test "formatting still falls back" do
    assert {:ok, "1,234.5"} = Localize.Number.to_string(1234.5, locale: @locale)
  end
end
