defmodule Localize.Locale.LocaleCacheDirTest do
  use ExUnit.Case, async: false

  # Regression coverage for the `:locale_cache_dir` / `:otp_app`
  # accepted-forms contract. See `Localize.LocaleCacheDirError` for
  # the design — single source of truth, no two-file pattern,
  # relative paths refused at app start.

  alias Localize.Locale.Provider
  alias Localize.LocaleCacheDirError

  setup do
    previous_dir = Application.get_env(:localize, :locale_cache_dir, :__unset__)
    previous_app = Application.get_env(:localize, :otp_app, :__unset__)

    on_exit(fn ->
      restore(:locale_cache_dir, previous_dir)
      restore(:otp_app, previous_app)
    end)

    :ok
  end

  defp restore(key, :__unset__), do: Application.delete_env(:localize, key)
  defp restore(key, value), do: Application.put_env(:localize, key, value)

  describe "no overrides" do
    test "falls back to the bundled :localize priv" do
      Application.delete_env(:localize, :locale_cache_dir)
      Application.delete_env(:localize, :otp_app)
      assert Provider.locale_cache_dir() == Provider.default_locale_cache_dir()
      assert Provider.validate_locale_cache_dir!() == :ok
    end
  end

  describe ":otp_app — the recommended form" do
    test "resolves via Application.app_dir/2 with the conventional subpath" do
      Application.delete_env(:localize, :locale_cache_dir)
      Application.put_env(:localize, :otp_app, :localize)

      assert Provider.locale_cache_dir() ==
               Application.app_dir(:localize, "priv/localize/locales")

      assert Provider.validate_locale_cache_dir!() == :ok
    end

    test "non-atom :otp_app raises :invalid_otp_app" do
      Application.delete_env(:localize, :locale_cache_dir)
      Application.put_env(:localize, :otp_app, "not_an_atom")

      error = assert_raise LocaleCacheDirError, fn -> Provider.locale_cache_dir() end
      assert error.reason == :invalid_otp_app
      assert error.value == "not_an_atom"
    end
  end

  describe ":locale_cache_dir — explicit absolute path" do
    test "returned verbatim" do
      Application.put_env(:localize, :locale_cache_dir, "/var/lib/localize/locales")
      assert Provider.locale_cache_dir() == "/var/lib/localize/locales"
      assert Provider.validate_locale_cache_dir!() == :ok
    end

    test "overrides :otp_app when both are set" do
      Application.put_env(:localize, :otp_app, :localize)
      Application.put_env(:localize, :locale_cache_dir, "/var/lib/elsewhere")
      assert Provider.locale_cache_dir() == "/var/lib/elsewhere"
    end
  end

  describe ":otp_app + relative :locale_cache_dir — anchored under the app" do
    test "resolves the relative path against Application.app_dir/2" do
      Application.put_env(:localize, :otp_app, :localize)
      Application.put_env(:localize, :locale_cache_dir, "priv/i18n/cache")

      assert Provider.locale_cache_dir() ==
               Application.app_dir(:localize, "priv/i18n/cache")

      assert Provider.validate_locale_cache_dir!() == :ok
    end

    test "./relative is also anchored" do
      Application.put_env(:localize, :otp_app, :localize)
      Application.put_env(:localize, :locale_cache_dir, "./priv/i18n/cache")

      assert Provider.locale_cache_dir() ==
               Application.app_dir(:localize, "./priv/i18n/cache")
    end

    test "non-atom :otp_app still raises :invalid_otp_app even with a relative path" do
      Application.put_env(:localize, :otp_app, "not_an_atom")
      Application.put_env(:localize, :locale_cache_dir, "priv/i18n/cache")

      error = assert_raise LocaleCacheDirError, fn -> Provider.locale_cache_dir() end
      assert error.reason == :invalid_otp_app
      assert error.value == "not_an_atom"
    end
  end

  describe ":locale_cache_dir — relative path without :otp_app is refused" do
    test "bare relative path raises :relative_path" do
      Application.delete_env(:localize, :otp_app)
      Application.put_env(:localize, :locale_cache_dir, "priv/localize/locales")

      error = assert_raise LocaleCacheDirError, fn -> Provider.locale_cache_dir() end
      assert error.reason == :relative_path
      assert error.value == "priv/localize/locales"

      # The message points the user at both remediation paths.
      message = Exception.message(error)
      assert message =~ "otp_app"
      assert message =~ "absolute"
    end

    test "./relative also raises when no :otp_app is set" do
      Application.delete_env(:localize, :otp_app)
      Application.put_env(:localize, :locale_cache_dir, "./priv/cache")
      assert_raise LocaleCacheDirError, ~r/relative path/, fn -> Provider.locale_cache_dir() end
    end

    test "validate_locale_cache_dir!/0 surfaces the same error at app-start time" do
      Application.delete_env(:localize, :otp_app)
      Application.put_env(:localize, :locale_cache_dir, "priv/x")
      assert_raise LocaleCacheDirError, fn -> Provider.validate_locale_cache_dir!() end
    end
  end

  describe ":locale_cache_dir — malformed value is refused" do
    test "an integer raises :invalid_form" do
      Application.put_env(:localize, :locale_cache_dir, 42)

      error = assert_raise LocaleCacheDirError, fn -> Provider.locale_cache_dir() end
      assert error.reason == :invalid_form
      assert error.value == 42
    end

    test "a tuple raises :invalid_form (no tagged-tuple shorthand)" do
      Application.put_env(:localize, :locale_cache_dir, {:app, :foo, "bar"})

      error = assert_raise LocaleCacheDirError, fn -> Provider.locale_cache_dir() end
      assert error.reason == :invalid_form
    end
  end

  describe "LocaleCacheDirError adopts the Localize.Exception behaviour" do
    test "reason_atoms/0 is exhaustive" do
      assert LocaleCacheDirError.reason_atoms() ==
               [:relative_path, :invalid_form, :invalid_otp_app]
    end

    test "every reason atom renders a non-empty message without struct leakage" do
      for reason <- LocaleCacheDirError.reason_atoms() do
        exception = LocaleCacheDirError.exception(reason: reason, value: "test")
        rendered = Exception.message(exception)
        assert rendered != ""
        refute String.contains?(rendered, "%Localize.")
      end
    end
  end
end
