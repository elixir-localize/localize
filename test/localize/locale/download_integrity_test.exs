defmodule Localize.Locale.Provider.DownloadIntegrityTest do
  # async: false because the tests swap the process-global hash
  # manifest via the persistent-term test seam.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Localize.Locale.Provider

  @body :erlang.term_to_binary(%{version: "test", data: "payload"})
  @url "https://example.invalid/locales/xx.etf"

  setup do
    on_exit(fn -> Provider.reset_locale_hashes() end)
    :ok
  end

  describe "verify_locale_integrity/3 with a manifest" do
    test "passes when the hash matches" do
      Provider.put_locale_hashes(%{xx: :crypto.hash(:sha256, @body)})

      assert {:ok, @body} = Provider.verify_locale_integrity(:xx, @url, @body)
    end

    test "fails closed on a hash mismatch" do
      Provider.put_locale_hashes(%{xx: :crypto.hash(:sha256, "different content")})

      assert {:error, %Localize.LocaleIntegrityError{reason: :hash_mismatch} = error} =
               Provider.verify_locale_integrity(:xx, @url, @body)

      message = Exception.message(error)
      assert message =~ "failed integrity verification"
      assert message =~ Base.encode16(:crypto.hash(:sha256, @body), case: :lower)
    end

    test "fails closed when the locale has no manifest entry" do
      Provider.put_locale_hashes(%{other: :crypto.hash(:sha256, @body)})

      assert {:error, %Localize.LocaleIntegrityError{reason: :no_manifest_entry}} =
               Provider.verify_locale_integrity(:xx, @url, @body)
    end

    test "a tampered single byte is detected" do
      Provider.put_locale_hashes(%{xx: :crypto.hash(:sha256, @body)})
      <<first, rest::binary>> = @body
      tampered = <<Bitwise.bxor(first, 1), rest::binary>>

      assert {:error, %Localize.LocaleIntegrityError{reason: :hash_mismatch}} =
               Provider.verify_locale_integrity(:xx, @url, tampered)
    end
  end

  describe "verify_locale_integrity/3 without a manifest" do
    test "passes the body through and warns once" do
      Provider.put_locale_hashes(:no_manifest)

      log =
        capture_log(fn ->
          assert {:ok, @body} = Provider.verify_locale_integrity(:xx, @url, @body)
        end)

      assert log =~ "will not be integrity-verified"

      # The warning is emitted only once.
      silent =
        capture_log(fn ->
          assert {:ok, @body} = Provider.verify_locale_integrity(:yy, @url, @body)
        end)

      assert silent == ""
    end
  end
end
