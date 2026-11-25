defmodule Localize.ContextTransformTest do
  use ExUnit.Case, async: true

  alias Localize.ContextTransform

  doctest Localize.ContextTransform

  # The name with its first letter titlecased, as titlecase-firstword
  # writes it.
  defp titled(name) do
    {first, rest} = String.next_grapheme(name)
    String.capitalize(first) <> rest
  end

  describe "transform/4" do
    test "cases a name for a menu or for standing alone, as the locale's data says" do
      assert ContextTransform.transform("français", :languages, :ui_list_or_menu, locale: :fr) ==
               {:ok, "Français"}

      assert ContextTransform.transform("janvier", :month_standalone_except_narrow, :stand_alone,
               locale: :fr
             ) ==
               {:ok, "Janvier"}
    end

    test "leaves a name in the middle of a sentence as CLDR writes it" do
      assert ContextTransform.transform("français", :languages, :middle_of_sentence, locale: :fr) ==
               {:ok, "français"}
    end

    test "titlecases the first word at the beginning of a sentence, in every locale" do
      assert ContextTransform.transform("deutsch", :languages, :begin_sentence, locale: :de) ==
               {:ok, "Deutsch"}

      assert ContextTransform.transform("euro", :currency_name, :begin_sentence, locale: :fr) ==
               {:ok, "Euro"}
    end

    test "leaves a name the locale has no transform for, or a no-change one" do
      # German has no context transforms.
      assert ContextTransform.transform("deutsch", :languages, :ui_list_or_menu, locale: :de) ==
               {:ok, "deutsch"}

      # European Portuguese keeps language names in lower case in a menu,
      # where Portuguese capitalizes them, and capitalizes them standing alone.
      assert ContextTransform.transform("português", :languages, :ui_list_or_menu,
               locale: "pt-PT"
             ) ==
               {:ok, "português"}

      assert ContextTransform.transform("português", :languages, :ui_list_or_menu, locale: "pt") ==
               {:ok, "Português"}
    end

    test "titlecases only the first letter, after any leading punctuation" do
      assert ContextTransform.transform("español (México)", :languages, :ui_list_or_menu,
               locale: :es
             ) ==
               {:ok, "Español (México)"}

      assert ContextTransform.transform("«français»", :languages, :begin_sentence, locale: :fr) ==
               {:ok, "«Français»"}

      assert ContextTransform.transform("", :languages, :begin_sentence, locale: :fr) == {:ok, ""}

      assert ContextTransform.transform("123", :languages, :begin_sentence, locale: :fr) ==
               {:ok, "123"}
    end

    test "follows the language's casing" do
      assert ContextTransform.transform("izlandaca", :languages, :begin_sentence, locale: :tr) ==
               {:ok, "İzlandaca"}

      assert ContextTransform.transform("izlandaca", :languages, :begin_sentence, locale: :en) ==
               {:ok, "Izlandaca"}

      assert ContextTransform.transform("ijslands", :languages, :begin_sentence, locale: :nl) ==
               {:ok, "IJslands"}

      # The digraph ǆ titlecases to ǅ, not to the capital Ǆ.
      assert ContextTransform.transform("ǆemal", :languages, :begin_sentence, locale: :hr) ==
               {:ok, "ǅemal"}
    end

    test "takes the current locale by default" do
      {:ok, _locale} = Localize.put_locale(:fr)

      assert ContextTransform.transform("français", :languages, :ui_list_or_menu) ==
               {:ok, "Français"}
    end

    test "returns an error, never raises, for anything that is not a name, a usage, a context or a locale" do
      assert {:error, %Localize.InvalidValueError{}} =
               ContextTransform.transform(42, :languages, :ui_list_or_menu, locale: :fr)

      assert {:error, %Localize.InvalidValueError{}} =
               ContextTransform.transform("x", :territories, :ui_list_or_menu, locale: :fr)

      assert {:error, %Localize.InvalidValueError{}} =
               ContextTransform.transform("x", :languages, :sideways, locale: :fr)

      assert {:error, _exception} =
               ContextTransform.transform("x", :languages, :ui_list_or_menu,
                 locale: "not a locale!"
               )

      assert {:error, _exception} =
               ContextTransform.transform("x", :languages, :ui_list_or_menu, %{})
    end
  end

  describe "the :capitalization option" do
    test "of locale and language display names" do
      {:ok, plain} = Localize.Locale.LocaleDisplay.display_name("fr", locale: :fr)

      assert Localize.Locale.LocaleDisplay.display_name("fr",
               locale: :fr,
               capitalization: :ui_list_or_menu
             ) ==
               {:ok, titled(plain)}

      {:ok, russian} = Localize.Language.display_name("ru", locale: :ru)

      assert Localize.Language.display_name("ru", locale: :ru, capitalization: :ui_list_or_menu) ==
               {:ok, titled(russian)}
    end

    test "of script, currency, calendar and era names, in a locale that transforms them" do
      options = [locale: :ru, capitalization: :ui_list_or_menu]

      for {plain, capitalized} <- [
            {Localize.Script.display_name(:Cyrl, locale: :ru),
             Localize.Script.display_name(:Cyrl, options)},
            {Localize.Currency.display_name(:RUB, locale: :ru),
             Localize.Currency.display_name(:RUB, options)},
            {Localize.Calendar.display_name(:calendar, :gregorian, locale: :ru),
             Localize.Calendar.display_name(:calendar, :gregorian, options)},
            {Localize.Calendar.display_name(:era, 1, locale: :ru),
             Localize.Calendar.display_name(:era, 1, options)}
          ] do
        {:ok, plain} = plain
        assert capitalized == {:ok, titled(plain)}
      end
    end

    test "of month and day names, which take the usage of their context and leave narrow names" do
      stand_alone = [locale: :fr, context: :stand_alone, capitalization: :stand_alone]

      assert Localize.Calendar.display_name(:month, 1, stand_alone) == {:ok, "Janvier"}
      assert Localize.Calendar.display_name(:day_of_week, 1, stand_alone) == {:ok, "Lundi"}

      assert Localize.Calendar.display_name(:month, 1, [{:style, :narrow} | stand_alone]) ==
               {:ok, "J"}

      assert Localize.Calendar.display_name(:month, 1, locale: :fr) == {:ok, "janvier"}
    end

    test "that is not a context returns an error" do
      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Language.display_name("fr", locale: :fr, capitalization: :sideways)
    end
  end
end
