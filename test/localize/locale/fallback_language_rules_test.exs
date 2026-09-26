defmodule Localize.Locale.FallbackLanguageRulesTest do
  # The provider is set in the application environment, which every
  # formatter reads, so no other test may run at the same time.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  # Like a release with downloads off: only the bundled en and und data
  # load. Every other locale falls back to en. The data is kept apart
  # from the default provider, which may hold the real ru and de-CH data.
  defmodule BundledOnlyProvider do
    @moduledoc false
    @behaviour Localize.Locale.Provider

    alias Localize.Locale.Provider.PersistentTerm

    @impl true
    def load(locale) when locale in [:en, :und], do: PersistentTerm.load(locale)

    def load(locale),
      do: {:error, Localize.LocaleNotFoundInCacheError.exception(locale_id: locale)}

    @impl true
    def store(locale_id, locale_data),
      do: :persistent_term.put({__MODULE__, locale_id}, locale_data)

    @impl true
    def loaded?(locale) do
      {:ok, locale_id} = Localize.Locale.cldr_locale_id_from(locale)
      :persistent_term.get({__MODULE__, locale_id}, nil) != nil
    end

    @impl true
    def get(locale, keys, _options) do
      {:ok, locale_id} = Localize.Locale.cldr_locale_id_from(locale)

      case get_in(:persistent_term.get({__MODULE__, locale_id}, %{}), keys) do
        nil -> {:error, Localize.ItemNotFoundError.exception(locale: locale_id, keys: keys)}
        value -> {:ok, value}
      end
    end
  end

  setup do
    previous = Application.fetch_env(:localize, :locale_provider)
    Application.put_env(:localize, :locale_provider, BundledOnlyProvider)

    on_exit(fn ->
      case previous do
        {:ok, provider} -> Application.put_env(:localize, :locale_provider, provider)
        :error -> Application.delete_env(:localize, :locale_provider)
      end
    end)

    capture_log(fn ->
      :ok = Localize.Locale.load_and_store(:ru)
      :ok = Localize.Locale.load_and_store(:"de-CH")
    end)

    :ok
  end

  test "ru and de-CH hold the en data and name en as their data locale" do
    assert Localize.Locale.data_locale_id(:ru) == :en
    assert Localize.Locale.data_locale_id(:"de-CH") == :en
    assert Localize.Locale.data_locale_id(:en) == :en
  end

  test "ru names 21 USD in the en plural: 21 US dollars, not 21 US dollar" do
    options = [currency: :USD, fractional_digits: 0, locale: :ru]

    assert Localize.Number.to_string(21, [format: :currency_long] ++ options) ==
             {:ok, "21 US dollars"}

    assert Localize.Number.to_string(21, [format: :currency_long_with_symbol] ++ options) ==
             {:ok, "$21 US dollars"}

    assert Localize.Number.to_string(21, [format: "#,##0 ¤¤¤"] ++ options) ==
             {:ok, "21 US dollars"}

    assert Localize.Currency.pluralize(21, :USD, locale: :ru) == {:ok, "US dollars"}
  end

  test "ru formats 21 in units with the en plural: 21 meters, 21 newton-meters, 1–21 days" do
    assert Localize.Unit.to_string(Localize.Unit.new!(21, "meter"), locale: :ru) ==
             {:ok, "21 meters"}

    assert Localize.Unit.to_string(Localize.Unit.new!(21, "newton-meter"), locale: :ru) ==
             {:ok, "21 newton-meters"}

    assert Localize.Unit.to_range_string(
             Localize.Unit.new!(1, "day"),
             Localize.Unit.new!(21, "day"),
             locale: :ru
           ) == {:ok, "1–21 days"}
  end

  test "ru selects its own registered unit strings with ru rules: 21 смут" do
    on_exit(fn -> Localize.Unit.CustomRegistry.clear() end)

    :ok =
      Localize.Unit.define_unit("smoot", %{
        base_unit: "meter",
        factor: 1.7018,
        category: "length",
        display: %{
          ru: %{
            long: %{one: "{0} смут", few: "{0} смута", many: "{0} смутов", other: "{0} смута"}
          }
        }
      })

    assert Localize.Unit.to_string(Localize.Unit.new!(21, "smoot"), locale: :ru) ==
             {:ok, "21 смут"}
  end

  test "ru formats 21 days ago and the ordinal 21st with en rules" do
    assert Localize.DateTime.Relative.to_string(-21, unit: :day, locale: :ru) ==
             {:ok, "21 days ago"}

    assert Localize.Number.to_string(21, format: :ordinal, locale: :ru) == {:ok, "21st"}
  end

  test "de-CH names day periods with en rules: 10 at night, 12 noon" do
    assert Localize.Time.to_string(~T[22:00:00], format: "h B", locale: :"de-CH") ==
             {:ok, "10 at night"}

    assert Localize.Time.to_string(~T[12:00:00], format: "h b", locale: :"de-CH") ==
             {:ok, "12 noon"}
  end

  test "de-CH keeps its territory preferences: CHF and Monday as the first day" do
    assert Localize.Number.to_string(1234, format: :currency, locale: :"de-CH") ==
             {:ok, "CHF 1,234.00"}

    assert Localize.Calendar.first_day_for_locale(:"de-CH") == 1
  end
end
