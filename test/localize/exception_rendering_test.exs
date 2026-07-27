defmodule Localize.ExceptionRenderingTest do
  use ExUnit.Case, async: true

  # Every Localize exception module must render a non-empty message
  # from `Exception.message/1` that includes the key binding values.
  # The message text is translation-backed (Gettext + MF2), so these
  # tests assert substrings rather than golden full strings.

  describe "Localize.BindError" do
    test "message includes the unbound variable" do
      exception = Localize.BindError.exception(unbound: :count)
      message = Exception.message(exception)
      assert is_binary(message)
      assert message =~ ":count"
    end
  end

  describe "Localize.CurrencyNoDisplayNameError" do
    test "message includes currency and locale" do
      exception = Localize.CurrencyNoDisplayNameError.exception(currency: :XYZ, locale: :fr)
      message = Exception.message(exception)
      assert message =~ ":XYZ"
      assert message =~ ":fr"
    end
  end

  describe "Localize.CurrencyNotLocalizedError" do
    test "message includes currency and locale" do
      exception = Localize.CurrencyNotLocalizedError.exception(currency: :VES, locale: :ja)
      message = Exception.message(exception)
      assert message =~ ":VES"
      assert message =~ ":ja"
    end
  end

  describe "Localize.DateTimeFormatError" do
    test "invalid_format reason includes the format" do
      exception = Localize.DateTimeFormatError.exception(format: "yyy%", reason: :invalid_format)
      message = Exception.message(exception)
      assert message =~ "yyy%"
    end

    test "tokenize_error reason includes format and detail" do
      exception =
        Localize.DateTimeFormatError.exception(
          format: "GGGGGG",
          reason: :tokenize_error,
          detail: :too_many_symbols
        )

      message = Exception.message(exception)
      assert message =~ "GGGGGG"
      assert message =~ ":too_many_symbols"
    end

    test "other reason includes format and reason" do
      exception =
        Localize.DateTimeFormatError.exception(format: "qq", reason: :unsupported_field)

      message = Exception.message(exception)
      assert message =~ "qq"
      assert message =~ ":unsupported_field"
    end

    test "nil reason falls back to invalid format message" do
      exception = Localize.DateTimeFormatError.exception(format: "??")
      message = Exception.message(exception)
      assert message =~ "??"
    end
  end

  describe "Localize.DateTimeIntervalFormatError" do
    test "unknown_fields reason includes fields and format" do
      exception =
        Localize.DateTimeIntervalFormatError.exception(
          reason: :unknown_fields,
          fields: :fancy,
          format: :long
        )

      message = Exception.message(exception)
      assert message =~ ":fancy"
      assert message =~ ":long"
    end

    test "no_format reason includes the format key" do
      exception =
        Localize.DateTimeIntervalFormatError.exception(reason: :no_format, format_key: :yMd)

      message = Exception.message(exception)
      assert message =~ ":yMd"
    end

    test "no_pattern reason includes format key and difference" do
      exception =
        Localize.DateTimeIntervalFormatError.exception(
          reason: :no_pattern,
          format_key: :yMMM,
          detail: :d
        )

      message = Exception.message(exception)
      assert message =~ ":yMMM"
      assert message =~ ":d"
    end

    test "invalid_format reason includes the detail" do
      exception =
        Localize.DateTimeIntervalFormatError.exception(reason: :invalid_format, detail: "y//M")

      message = Exception.message(exception)
      assert message =~ "y//M"
    end

    test "unterminated_quote reason renders a non-empty message" do
      exception = Localize.DateTimeIntervalFormatError.exception(reason: :unterminated_quote)
      message = Exception.message(exception)
      assert is_binary(message)
      assert message != ""
    end

    test "no_fallback reason renders a non-empty message" do
      exception = Localize.DateTimeIntervalFormatError.exception(reason: :no_fallback)
      message = Exception.message(exception)
      assert is_binary(message)
      assert message != ""
    end
  end

  describe "Localize.DateTimeInvalidInputError" do
    test "time type mentions the required time keys" do
      exception = Localize.DateTimeInvalidInputError.exception(type: :time)
      assert Exception.message(exception) =~ "hour"
    end

    test "date type mentions the required date keys" do
      exception = Localize.DateTimeInvalidInputError.exception(type: :date)
      assert Exception.message(exception) =~ "year"
    end

    test "datetime type mentions date and time keys" do
      exception = Localize.DateTimeInvalidInputError.exception(type: :datetime)
      assert Exception.message(exception) =~ "date"
    end
  end

  describe "Localize.DateTimeUnresolvedFormatError" do
    test "message includes format and locale" do
      exception =
        Localize.DateTimeUnresolvedFormatError.exception(format: :yMdjms, locale: :"en-AU")

      message = Exception.message(exception)
      assert message =~ ":yMdjms"
      assert message =~ "en-AU"
    end
  end

  describe "Localize.FormatError" do
    test "unbalanced_markup without detail includes the value" do
      exception = Localize.FormatError.exception(reason: :unbalanced_markup, value: "{#b}oops")
      message = Exception.message(exception)
      assert message =~ "{#b}oops"
    end

    test "unbalanced_markup with detail includes value and detail" do
      exception =
        Localize.FormatError.exception(
          reason: :unbalanced_markup,
          value: "{#b}oops",
          detail: "unclosed b"
        )

      message = Exception.message(exception)
      assert message =~ "{#b}oops"
      assert message =~ "unclosed b"
    end

    test "mismatched_close includes the closing tag detail" do
      exception =
        Localize.FormatError.exception(reason: :mismatched_close, value: "{#b}x{/i}", detail: "i")

      message = Exception.message(exception)
      assert message =~ "{#b}x{/i}"
      assert message =~ "i"
    end

    test "mismatched_close with nil detail uses the unknown placeholder" do
      exception = Localize.FormatError.exception(reason: :mismatched_close, value: "{/i}")
      message = Exception.message(exception)
      assert message =~ "(unknown)"
    end

    test "formatter_failed with a cause delegates to the cause message" do
      cause = %RuntimeError{message: "downstream boom"}
      exception = Localize.FormatError.exception(reason: :formatter_failed, cause: cause)
      assert Exception.message(exception) == "downstream boom"
    end

    test "formatter_failed with a detail string returns the detail" do
      exception = Localize.FormatError.exception(reason: :formatter_failed, detail: "bad input")
      assert Exception.message(exception) == "bad input"
    end

    test "downstream_failure with a cause delegates to the cause message" do
      cause = Localize.UnknownUnitError.exception(unit: "furlong-per-fortnight")
      exception = Localize.FormatError.exception(reason: :downstream_failure, cause: cause)
      assert Exception.message(exception) =~ "furlong-per-fortnight"
    end

    test "fallback with detail includes value, function, and detail" do
      exception =
        Localize.FormatError.exception(value: 1.5, function: :integer, detail: "not an integer")

      message = Exception.message(exception)
      assert message =~ "1.5"
      assert message =~ ":integer"
      assert message =~ "not an integer"
    end

    test "fallback without detail includes value and function" do
      exception = Localize.FormatError.exception(value: ~D[2025-01-01], function: :number)
      message = Exception.message(exception)
      assert message =~ "2025-01-01"
      assert message =~ ":number"
    end
  end

  describe "Localize.InvalidLocaleError" do
    test "message includes the locale identifier" do
      exception = Localize.InvalidLocaleError.exception(locale_id: "no_good")
      assert Exception.message(exception) =~ "no_good"
    end
  end

  describe "Localize.InvalidSubtagError" do
    test "date_not_last reason includes value and key" do
      exception =
        Localize.InvalidSubtagError.exception(reason: :date_not_last, key: :sd, value: "2024")

      message = Exception.message(exception)
      assert message =~ "2024"
      assert message =~ ":sd"
    end

    test "unknown_script reason includes the value" do
      exception = Localize.InvalidSubtagError.exception(reason: :unknown_script, value: "Qqqq")
      assert Exception.message(exception) =~ "Qqqq"
    end

    test "invalid_key reason includes the key" do
      exception = Localize.InvalidSubtagError.exception(reason: :invalid_key, key: "zz")
      assert Exception.message(exception) =~ "zz"
    end

    test "fallback clause includes key and value" do
      exception = Localize.InvalidSubtagError.exception(key: :ca, value: "nocalendar")
      message = Exception.message(exception)
      assert message =~ ":ca"
      assert message =~ "nocalendar"
    end
  end

  describe "Localize.InvalidValueError" do
    test "atom expected with allowed values lists them" do
      exception =
        Localize.InvalidValueError.exception(
          value: :sideways,
          expected: :rounding_mode,
          allowed_values: [:up, :down]
        )

      message = Exception.message(exception)
      assert message =~ "rounding mode"
      assert message =~ ":sideways"
      assert message =~ ":up"
    end

    test "atom expected with context includes the context" do
      exception =
        Localize.InvalidValueError.exception(
          value: "week",
          expected: :time_unit,
          context: :duration
        )

      message = Exception.message(exception)
      assert message =~ "time unit"
      assert message =~ "week"
      assert message =~ ":duration"
    end

    test "string expected without context includes expectation and value" do
      exception =
        Localize.InvalidValueError.exception(value: -1, expected: "a positive integer")

      message = Exception.message(exception)
      assert message =~ "a positive integer"
      assert message =~ "-1"
    end

    test "string expected with context includes all three" do
      exception =
        Localize.InvalidValueError.exception(
          value: 0,
          expected: "a non-zero number",
          context: "unit conversion"
        )

      message = Exception.message(exception)
      assert message =~ "a non-zero number"
      assert message =~ "unit conversion"
      assert message =~ "0"
    end
  end

  describe "Localize.ItemNotFoundError" do
    test "message includes the key path and locale" do
      exception = Localize.ItemNotFoundError.exception(locale: :de, keys: [:units, :length])
      message = Exception.message(exception)
      assert message =~ ":de"
      assert message =~ ":units"
    end
  end

  describe "Localize.LikelySubtagsError" do
    test "message includes the locale" do
      exception = Localize.LikelySubtagsError.exception(locale: "xx-XX")
      assert Exception.message(exception) =~ "xx-XX"
    end
  end

  describe "Localize.LocaleCacheDirError" do
    test "relative_path reason includes the offending value" do
      exception =
        Localize.LocaleCacheDirError.exception(reason: :relative_path, value: "priv/cache")

      message = Exception.message(exception)
      assert message =~ "priv/cache"
      assert message =~ ":otp_app"
    end

    test "invalid_form reason includes the offending value" do
      exception = Localize.LocaleCacheDirError.exception(reason: :invalid_form, value: 42)
      assert Exception.message(exception) =~ "42"
    end

    test "invalid_otp_app reason includes the offending value" do
      exception = Localize.LocaleCacheDirError.exception(reason: :invalid_otp_app, value: "app")
      assert Exception.message(exception) =~ "\"app\""
    end
  end

  describe "Localize.LocaleCacheWriteError" do
    test "permission_denied reason includes locale and path" do
      exception =
        Localize.LocaleCacheWriteError.exception(
          locale_id: :fr,
          path: "/var/cache/fr.etf",
          reason: :permission_denied
        )

      message = Exception.message(exception)
      assert message =~ ":fr"
      assert message =~ "/var/cache/fr.etf"
      assert message =~ "permission"
    end

    test "posix :eacces is normalized to permission_denied" do
      exception =
        Localize.LocaleCacheWriteError.exception(
          locale_id: :fr,
          path: "/var/cache/fr.etf",
          posix_error: :eacces
        )

      assert exception.reason == :permission_denied
    end

    test "no_such_directory reason includes locale and path" do
      exception =
        Localize.LocaleCacheWriteError.exception(
          locale_id: :de,
          path: "/missing/de.etf",
          reason: :no_such_directory
        )

      message = Exception.message(exception)
      assert message =~ ":de"
      assert message =~ "/missing/de.etf"
    end

    test "disk_full reason includes locale and path" do
      exception =
        Localize.LocaleCacheWriteError.exception(
          locale_id: :ja,
          path: "/full/ja.etf",
          reason: :disk_full
        )

      message = Exception.message(exception)
      assert message =~ ":ja"
      assert message =~ "/full/ja.etf"
    end

    test "read_only_filesystem reason includes locale and path" do
      exception =
        Localize.LocaleCacheWriteError.exception(
          locale_id: :es,
          path: "/ro/es.etf",
          reason: :read_only_filesystem
        )

      message = Exception.message(exception)
      assert message =~ ":es"
      assert message =~ "read-only"
    end

    test "file_exists reason includes locale and path" do
      exception =
        Localize.LocaleCacheWriteError.exception(
          locale_id: :it,
          path: "/dup/it.etf",
          reason: :file_exists
        )

      message = Exception.message(exception)
      assert message =~ ":it"
      assert message =~ "/dup/it.etf"
    end

    test "other_io_error reason includes the posix error" do
      exception =
        Localize.LocaleCacheWriteError.exception(
          locale_id: :pt,
          path: "/odd/pt.etf",
          reason: :other_io_error,
          posix_error: :ebusy
        )

      message = Exception.message(exception)
      assert message =~ ":pt"
      assert message =~ ":ebusy"
    end
  end

  describe "Localize.LocaleDisplayError" do
    test "message includes the locale" do
      exception = Localize.LocaleDisplayError.exception(locale: :"zh-Hant")
      assert Exception.message(exception) =~ "zh-Hant"
    end
  end

  describe "Localize.LocaleDownloadError" do
    @download_url "https://example.com/locales/fr.etf"

    test "not_modified reason includes locale and url" do
      exception =
        Localize.LocaleDownloadError.exception(
          locale_id: :fr,
          url: @download_url,
          reason: :not_modified
        )

      message = Exception.message(exception)
      assert message =~ ":fr"
      assert message =~ @download_url
    end

    test "http_error reason includes the HTTP status" do
      exception =
        Localize.LocaleDownloadError.exception(
          locale_id: :fr,
          url: @download_url,
          reason: :http_error,
          http_status: 404
        )

      message = Exception.message(exception)
      assert message =~ "404"
      assert message =~ @download_url
    end

    test "an integer cause is normalized to http_error with status" do
      exception =
        Localize.LocaleDownloadError.exception(locale_id: :fr, url: @download_url, cause: 503)

      assert exception.reason == :http_error
      assert exception.http_status == 503
      assert Exception.message(exception) =~ "503"
    end

    test "connection_timeout reason renders locale and url" do
      exception =
        Localize.LocaleDownloadError.exception(
          locale_id: :fr,
          url: @download_url,
          reason: :connection_timeout
        )

      assert Exception.message(exception) =~ @download_url
    end

    test "request_timeout reason renders locale and url" do
      exception =
        Localize.LocaleDownloadError.exception(
          locale_id: :fr,
          url: @download_url,
          reason: :request_timeout
        )

      assert Exception.message(exception) =~ @download_url
    end

    test "nxdomain reason renders locale and url" do
      exception =
        Localize.LocaleDownloadError.exception(
          locale_id: :fr,
          url: @download_url,
          reason: :nxdomain
        )

      assert Exception.message(exception) =~ @download_url
    end

    test "network_error reason includes the cause" do
      exception =
        Localize.LocaleDownloadError.exception(
          locale_id: :fr,
          url: @download_url,
          reason: :network_error,
          cause: :econnrefused
        )

      assert Exception.message(exception) =~ ":econnrefused"
    end

    test "safe_decode_failed reason renders locale and url" do
      exception =
        Localize.LocaleDownloadError.exception(
          locale_id: :fr,
          url: @download_url,
          reason: :safe_decode_failed
        )

      assert Exception.message(exception) =~ @download_url
    end

    test "stale_version reason renders locale and url" do
      exception =
        Localize.LocaleDownloadError.exception(
          locale_id: :fr,
          url: @download_url,
          reason: :stale_version
        )

      assert Exception.message(exception) =~ @download_url
    end

    test "fallback clause renders when reason is unset on the struct" do
      exception = %Localize.LocaleDownloadError{
        locale_id: :fr,
        url: @download_url,
        cause: :mystery
      }

      message = Exception.message(exception)
      assert message =~ ":mystery"
      assert message =~ @download_url
    end
  end

  describe "Localize.LocaleIntegrityError" do
    test "no_manifest_entry reason includes locale and url" do
      exception =
        Localize.LocaleIntegrityError.exception(
          locale_id: :fr,
          url: "https://example.com/fr.etf",
          reason: :no_manifest_entry
        )

      message = Exception.message(exception)
      assert message =~ ":fr"
      assert message =~ "https://example.com/fr.etf"
    end

    test "hash_mismatch reason includes expected and actual hashes" do
      exception =
        Localize.LocaleIntegrityError.exception(
          locale_id: :fr,
          url: "https://example.com/fr.etf",
          reason: :hash_mismatch,
          expected: "abc123",
          actual: "def456"
        )

      message = Exception.message(exception)
      assert message =~ "abc123"
      assert message =~ "def456"
    end
  end

  describe "Localize.LocaleIsStaleError" do
    test "message includes locale and both versions" do
      exception =
        Localize.LocaleIsStaleError.exception(
          locale_id: :fr,
          cached_version: "1.0.0",
          current_version: "2.0.0"
        )

      message = Exception.message(exception)
      assert message =~ ":fr"
      assert message =~ "1.0.0"
      assert message =~ "2.0.0"
    end
  end

  describe "Localize.LocaleMatchError" do
    test "message includes the desired locale and threshold" do
      exception = Localize.LocaleMatchError.exception(desired: "gsw-LI", threshold: 10)
      message = Exception.message(exception)
      assert message =~ "gsw-LI"
      assert message =~ "10"
    end
  end

  describe "Localize.LocaleNotFoundInCacheError" do
    test "without a posix error includes the download hint" do
      exception =
        Localize.LocaleNotFoundInCacheError.exception(
          locale_id: :fr,
          path: "/cache/fr.etf"
        )

      message = Exception.message(exception)
      assert message =~ ":fr"
      assert message =~ "/cache/fr.etf"
      assert message =~ "localize.download_locales"
    end

    test "with a posix error includes the reason" do
      exception =
        Localize.LocaleNotFoundInCacheError.exception(
          locale_id: :fr,
          path: "/cache/fr.etf",
          posix_error: :eacces
        )

      message = Exception.message(exception)
      assert message =~ ":fr"
      assert message =~ ":eacces"
    end
  end

  describe "Localize.NoCertificateStoreError" do
    test "message includes the searched paths" do
      exception =
        Localize.NoCertificateStoreError.exception(
          searched: ["/etc/ssl/cert.pem", "/usr/lib/ssl/certs"]
        )

      message = Exception.message(exception)
      assert message =~ "/etc/ssl/cert.pem"
      assert message =~ "castore"
    end
  end

  describe "Localize.NoParentError" do
    test "message includes the locale" do
      exception = Localize.NoParentError.exception(locale: :und)
      assert Exception.message(exception) =~ ":und"
    end
  end

  describe "Localize.NoParentTerritoryError" do
    test "message includes the territory" do
      exception = Localize.NoParentTerritoryError.exception(territory: :"001")
      assert Exception.message(exception) =~ "001"
    end
  end

  describe "Localize.NoPracticalDifferenceError" do
    test "message includes both datetime values" do
      exception =
        Localize.NoPracticalDifferenceError.exception(
          from: ~D[2025-01-01],
          to: ~D[2025-01-01]
        )

      assert Exception.message(exception) =~ "2025-01-01"
    end
  end

  describe "Localize.ParseError" do
    test "unexpected_trailing_input with line and column locates the error" do
      exception =
        Localize.ParseError.exception(
          input: "hello\nworld!",
          offset: 11,
          reason: :unexpected_trailing_input,
          rest: "!"
        )

      message = Exception.message(exception)
      assert message =~ "hello"
      assert message =~ "line 2"
      assert message =~ "column 6"
      assert message =~ "!"
    end

    test "unexpected_trailing_input without location includes input and rest" do
      exception =
        Localize.ParseError.exception(
          input: "en-US-xx",
          reason: :unexpected_trailing_input,
          rest: "-xx"
        )

      message = Exception.message(exception)
      assert message =~ "en-US-xx"
      assert message =~ "-xx"
    end

    test "unexpected_input with line and column includes detail and rest" do
      exception =
        Localize.ParseError.exception(
          input: "{$a b}",
          offset: 4,
          reason: :unexpected_input,
          detail: "expected }",
          rest: "b}"
        )

      message = Exception.message(exception)
      assert message =~ "expected }"
      assert message =~ "line 1"
      assert message =~ "column 5"
      assert message =~ "b}"
    end

    test "unexpected_input without location includes input and detail" do
      exception =
        Localize.ParseError.exception(
          input: "meter-per",
          reason: :unexpected_input,
          detail: "incomplete compound unit"
        )

      message = Exception.message(exception)
      assert message =~ "meter-per"
      assert message =~ "incomplete compound unit"
    end

    test "incomplete_input includes the input" do
      exception = Localize.ParseError.exception(input: "{$name", reason: :incomplete_input)
      message = Exception.message(exception)
      assert message =~ "{$name"
      assert message =~ "ended unexpectedly"
    end

    test "invalid_message_format includes input and detail" do
      exception =
        Localize.ParseError.exception(
          input: ".match {$n}",
          reason: :invalid_message_format,
          detail: "missing variants"
        )

      message = Exception.message(exception)
      assert message =~ ".match"
      assert message =~ "missing variants"
    end

    test "fallback with detail includes both" do
      exception = Localize.ParseError.exception(input: "zz-!!", detail: "invalid subtag")
      message = Exception.message(exception)
      assert message =~ "zz-!!"
      assert message =~ "invalid subtag"
    end

    test "fallback without detail includes the input" do
      exception = Localize.ParseError.exception(input: "not-a-tag")
      assert Exception.message(exception) =~ "not-a-tag"
    end
  end

  describe "Localize.UnitConversionError" do
    test "not_convertible reason includes both units" do
      exception =
        Localize.UnitConversionError.exception(
          from: :meter,
          to: :liter,
          reason: :not_convertible
        )

      message = Exception.message(exception)
      assert message =~ ":meter"
      assert message =~ ":liter"
    end

    test "special_conversion reason includes the source unit" do
      exception =
        Localize.UnitConversionError.exception(from: :beaufort, reason: :special_conversion)

      assert Exception.message(exception) =~ ":beaufort"
    end

    test "mixed_units reason renders a non-empty message" do
      exception = Localize.UnitConversionError.exception(reason: :mixed_units)
      message = Exception.message(exception)
      assert is_binary(message)
      assert message =~ "mixed"
    end

    test "fallback clause includes both units" do
      exception = Localize.UnitConversionError.exception(from: :second, to: :kelvin)
      message = Exception.message(exception)
      assert message =~ ":second"
      assert message =~ ":kelvin"
    end
  end

  describe "Localize.UnitNoValueError" do
    test "message includes the operation" do
      exception = Localize.UnitNoValueError.exception(operation: :convert)
      assert Exception.message(exception) =~ "convert"
    end
  end

  describe "Localize.UnitPreferenceError" do
    test "unknown_quantity reason includes the unit" do
      exception = Localize.UnitPreferenceError.exception(reason: :unknown_quantity, unit: :zorp)
      assert Exception.message(exception) =~ ":zorp"
    end

    test "unknown_category reason includes the quantity" do
      exception =
        Localize.UnitPreferenceError.exception(reason: :unknown_category, quantity: :zorpness)

      assert Exception.message(exception) =~ ":zorpness"
    end

    test "no_preference_for_usage reason includes category and usage" do
      exception =
        Localize.UnitPreferenceError.exception(
          reason: :no_preference_for_usage,
          category: :length,
          usage: :interstellar
        )

      message = Exception.message(exception)
      assert message =~ ":length"
      assert message =~ ":interstellar"
    end

    test "no_preference_for_region reason includes category and region" do
      exception =
        Localize.UnitPreferenceError.exception(
          reason: :no_preference_for_region,
          category: :length,
          region: :ZZ
        )

      message = Exception.message(exception)
      assert message =~ ":length"
      assert message =~ ":ZZ"
    end
  end

  describe "Localize.UnknownCalendarError" do
    test "message includes the calendar" do
      exception = Localize.UnknownCalendarError.exception(calendar: :klingon)
      assert Exception.message(exception) =~ ":klingon"
    end
  end

  describe "Localize.UnknownCurrencyError" do
    test "message includes the currency" do
      exception = Localize.UnknownCurrencyError.exception(currency: "ZZZ")
      assert Exception.message(exception) =~ "ZZZ"
    end
  end

  describe "Localize.UnknownLanguageError" do
    test "message includes the language" do
      exception = Localize.UnknownLanguageError.exception(language: "qq")
      assert Exception.message(exception) =~ "qq"
    end
  end

  describe "Localize.UnknownLocaleError" do
    test "message includes the locale identifier" do
      exception = Localize.UnknownLocaleError.exception(locale_id: :"xx-XX")
      assert Exception.message(exception) =~ "xx-XX"
    end
  end

  describe "Localize.UnknownMeasurementSystemError" do
    test "message includes the measurement system" do
      exception =
        Localize.UnknownMeasurementSystemError.exception(measurement_system: :imperial_plus)

      assert Exception.message(exception) =~ ":imperial_plus"
    end
  end

  describe "Localize.UnknownNumberSystemError" do
    test "not_for_locale reason includes system and locale" do
      exception =
        Localize.UnknownNumberSystemError.exception(
          reason: :not_for_locale,
          number_system: :thai,
          locale: :en
        )

      message = Exception.message(exception)
      assert message =~ ":thai"
      assert message =~ ":en"
    end

    test "fallback clause includes the number system" do
      exception = Localize.UnknownNumberSystemError.exception(number_system: :quintal)
      assert Exception.message(exception) =~ ":quintal"
    end
  end

  describe "Localize.UnknownPluralRulesError" do
    test "with a type includes the type and locale" do
      exception = Localize.UnknownPluralRulesError.exception(locale_id: :xx, type: :cardinal)
      message = Exception.message(exception)
      assert message =~ "cardinal"
      assert message =~ ":xx"
    end

    test "without a type includes the locale" do
      exception = Localize.UnknownPluralRulesError.exception(locale_id: :yy)
      assert Exception.message(exception) =~ ":yy"
    end
  end

  describe "Localize.UnknownRbnfRuleError" do
    test "message includes rule name and locale" do
      exception =
        Localize.UnknownRbnfRuleError.exception(rule_name: :spellout_ordinal_verbose, locale: :en)

      message = Exception.message(exception)
      assert message =~ ":spellout_ordinal_verbose"
      assert message =~ ":en"
    end
  end

  describe "Localize.UnknownScriptError" do
    test "message includes the script" do
      exception = Localize.UnknownScriptError.exception(script: "Qaaz")
      assert Exception.message(exception) =~ "Qaaz"
    end
  end

  describe "Localize.UnknownStyleError" do
    test "without a territory includes the style" do
      exception = Localize.UnknownStyleError.exception(style: :flamboyant)
      assert Exception.message(exception) =~ ":flamboyant"
    end

    test "with a territory includes style and territory" do
      exception = Localize.UnknownStyleError.exception(style: :flamboyant, territory: :US)
      message = Exception.message(exception)
      assert message =~ ":flamboyant"
      assert message =~ ":US"
    end
  end

  describe "Localize.UnknownSubdivisionError" do
    test "message includes the subdivision" do
      exception = Localize.UnknownSubdivisionError.exception(subdivision: "uszz")
      assert Exception.message(exception) =~ "uszz"
    end
  end

  describe "Localize.UnknownTerritoryError" do
    test "message includes the territory" do
      exception = Localize.UnknownTerritoryError.exception(territory: :ZZ)
      assert Exception.message(exception) =~ ":ZZ"
    end
  end

  describe "Localize.UnknownTimezoneError" do
    test "message includes the timezone" do
      exception = Localize.UnknownTimezoneError.exception(timezone: "Mars/Olympus_Mons")
      assert Exception.message(exception) =~ "Mars/Olympus_Mons"
    end
  end

  describe "Localize.UnknownUnitError" do
    test "message includes the unit" do
      exception = Localize.UnknownUnitError.exception(unit: "smidgen")
      assert Exception.message(exception) =~ "smidgen"
    end
  end

  describe "Localize.Exception.safe_message/3" do
    test "renders a template with no bindings using the default argument" do
      message = Localize.Exception.safe_message("unit", "Cannot compute anything here.")
      assert is_binary(message)
      assert message =~ "Cannot compute"
    end
  end

  describe "raise/rescue round-trips" do
    test "UnknownCurrencyError raises with a rendered message" do
      error =
        assert_raise Localize.UnknownCurrencyError, fn ->
          raise Localize.UnknownCurrencyError, currency: :ZZZ
        end

      assert Exception.message(error) =~ ":ZZZ"
    end

    test "LocaleIsStaleError raises with a rendered message" do
      error =
        assert_raise Localize.LocaleIsStaleError, fn ->
          raise Localize.LocaleIsStaleError,
            locale_id: :fr,
            cached_version: "1.0.0",
            current_version: "2.0.0"
        end

      assert Exception.message(error) =~ "2.0.0"
    end

    test "DateTimeIntervalFormatError raises with a rendered message" do
      error =
        assert_raise Localize.DateTimeIntervalFormatError, fn ->
          raise Localize.DateTimeIntervalFormatError, reason: :no_format, format_key: :yMd
        end

      assert Exception.message(error) =~ ":yMd"
    end

    test "ParseError is raised by LanguageTag.new!/1 with location context" do
      error =
        assert_raise Localize.ParseError, fn ->
          Localize.LanguageTag.new!("!!!")
        end

      assert Exception.message(error) =~ "!!!"
    end
  end
end
