defmodule Localize.Locale.GettextLocaleIdTest do
  use ExUnit.Case, async: true

  alias Localize.Locale

  defmodule SwissBackend do
    def __gettext__(:known_locales), do: ["de", "en", "fr", "it"]
    def __gettext__(_), do: nil
  end

  defmodule SwissGermanBackend do
    def __gettext__(:known_locales), do: ["de", "de_CH", "en"]
    def __gettext__(_), do: nil
  end

  test "de-CH matches de with de, en, fr, it and de_CH when the backend also knows de_CH, on every call" do
    {:ok, tag} = Localize.validate_locale("de-CH")

    for _call <- 1..2 do
      assert {:ok, "de"} = Locale.gettext_locale_id(tag, SwissBackend)
      assert {:ok, "de_CH"} = Locale.gettext_locale_id(tag, SwissGermanBackend)
      assert {:ok, "de_CH"} = Locale.gettext_locale_id("de-CH", SwissGermanBackend)
      assert {:ok, "fr"} = Locale.gettext_locale_id(:"fr-CH", SwissBackend)
    end
  end
end
