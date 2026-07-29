defmodule Localize.Exception.StructuralTest do
  use ExUnit.Case, async: true

  doctest Localize.ParseError

  # Every Localize exception that adopts `Localize.Exception` exposes
  # the exhaustive list of `:reason` atoms it supports. This test
  # iterates that list and asserts that `Exception.message/1`
  # produces a non-empty, well-formed string for each atom — catching
  # the failure mode where a new reason atom is declared in
  # `reason_atoms/0` but the `message/1` clause for it is forgotten.

  @modules [
    Localize.FormatError,
    Localize.LocaleCacheWriteError,
    Localize.LocaleDownloadError,
    Localize.ParseError
  ]

  # Per-(module, reason) realistic field bindings. Any reason that
  # appears in `reason_atoms/0` must have an entry here; the
  # `all reasons covered` test enforces that.

  @fixtures %{
    {Localize.FormatError, :unbalanced_markup} => [
      value: "{#open}no close",
      function: :format,
      reason: :unbalanced_markup
    ],
    {Localize.FormatError, :mismatched_close} => [
      value: "{#a}{/b}",
      function: :format,
      reason: :mismatched_close,
      detail: "\"b\""
    ],
    {Localize.FormatError, :formatter_failed} => [
      value: "{$x :number}",
      function: :format,
      reason: :formatter_failed,
      detail: "cannot format [1, 2, 3] as a number"
    ],
    {Localize.FormatError, :downstream_failure} => [
      value: "msg",
      function: :format,
      reason: :downstream_failure,
      cause: %RuntimeError{message: "underlying failure"}
    ],
    {Localize.FormatError, :duplicate_declaration} => [
      value: ".input {$var} .input {$var} {{_}}",
      function: :format,
      reason: :duplicate_declaration,
      detail: "var"
    ],
    {Localize.FormatError, :duplicate_option_name} => [
      value: "{42 :number style=percent style=decimal}",
      function: :format,
      reason: :duplicate_option_name,
      detail: "style"
    ],
    {Localize.FormatError, :duplicate_variant} => [
      value: ".input {$x :string} .match $x * {{a}} * {{b}}",
      function: :format,
      reason: :duplicate_variant,
      detail: "*"
    ],
    {Localize.FormatError, :missing_selector_annotation} => [
      value: ".input {$x} .match $x one {{a}} * {{b}}",
      function: :format,
      reason: :missing_selector_annotation,
      detail: "x"
    ],
    {Localize.FormatError, :variant_key_mismatch} => [
      value: ".input {$x :string} .match $x a b {{ab}} * {{fallback}}",
      function: :format,
      reason: :variant_key_mismatch,
      detail: "a b"
    ],
    {Localize.FormatError, :missing_fallback_variant} => [
      value: ".input {$x :number} .match $x one {{one}}",
      function: :format,
      reason: :missing_fallback_variant,
      detail: "*"
    ],
    {Localize.FormatError, :unknown_function} => [
      value: "{$x :nonexistent}",
      function: :format,
      reason: :unknown_function,
      detail: ":nonexistent"
    ],
    {Localize.LocaleCacheWriteError, :permission_denied} => [
      locale_id: :en,
      path: "/tmp/en.etf",
      reason: :permission_denied,
      posix_error: :eacces
    ],
    {Localize.LocaleCacheWriteError, :no_such_directory} => [
      locale_id: :en,
      path: "/tmp/en.etf",
      reason: :no_such_directory,
      posix_error: :enoent
    ],
    {Localize.LocaleCacheWriteError, :disk_full} => [
      locale_id: :en,
      path: "/tmp/en.etf",
      reason: :disk_full,
      posix_error: :enospc
    ],
    {Localize.LocaleCacheWriteError, :read_only_filesystem} => [
      locale_id: :en,
      path: "/tmp/en.etf",
      reason: :read_only_filesystem,
      posix_error: :erofs
    ],
    {Localize.LocaleCacheWriteError, :file_exists} => [
      locale_id: :en,
      path: "/tmp/en.etf",
      reason: :file_exists,
      posix_error: :eexist
    ],
    {Localize.LocaleCacheWriteError, :other_io_error} => [
      locale_id: :en,
      path: "/tmp/en.etf",
      reason: :other_io_error,
      posix_error: :eio
    ],
    {Localize.LocaleDownloadError, :not_modified} => [
      locale_id: :en,
      url: "https://example.com/en.etf",
      reason: :not_modified
    ],
    {Localize.LocaleDownloadError, :http_error} => [
      locale_id: :en,
      url: "https://example.com/en.etf",
      reason: :http_error,
      http_status: 404
    ],
    {Localize.LocaleDownloadError, :connection_timeout} => [
      locale_id: :en,
      url: "https://example.com/en.etf",
      reason: :connection_timeout
    ],
    {Localize.LocaleDownloadError, :request_timeout} => [
      locale_id: :en,
      url: "https://example.com/en.etf",
      reason: :request_timeout
    ],
    {Localize.LocaleDownloadError, :nxdomain} => [
      locale_id: :en,
      url: "https://example.com/en.etf",
      reason: :nxdomain
    ],
    {Localize.LocaleDownloadError, :network_error} => [
      locale_id: :en,
      url: "https://example.com/en.etf",
      reason: :network_error,
      cause: :econnrefused
    ],
    {Localize.LocaleDownloadError, :safe_decode_failed} => [
      locale_id: :en,
      url: "https://example.com/en.etf",
      reason: :safe_decode_failed
    ],
    {Localize.LocaleDownloadError, :stale_version} => [
      locale_id: :en,
      url: "https://example.com/en.etf",
      reason: :stale_version
    ],
    {Localize.ParseError, :unexpected_trailing_input} => [
      input: "Hello {extra",
      reason: :unexpected_trailing_input,
      offset: 6,
      rest: "{extra"
    ],
    {Localize.ParseError, :unexpected_input} => [
      input: "Hello {",
      reason: :unexpected_input,
      detail: "expected closing brace",
      offset: 6,
      rest: "{"
    ],
    {Localize.ParseError, :incomplete_input} => [input: "Hello {", reason: :incomplete_input],
    {Localize.ParseError, :invalid_message_format} => [
      input: "bad",
      reason: :invalid_message_format,
      detail: "ICU MF2 rejected the pattern"
    ]
  }

  for module <- @modules do
    describe "#{inspect(module)} structural exception" do
      test "adopts Localize.Exception behaviour" do
        behaviours = unquote(module).module_info(:attributes) |> Keyword.get_values(:behaviour)
        assert Localize.Exception in List.flatten(behaviours)
      end

      test "reason_atoms/0 returns a non-empty list of atoms" do
        atoms = unquote(module).reason_atoms()
        assert match?([_ | _], atoms)
        for atom <- atoms, do: assert(is_atom(atom))
      end

      test "every reason atom has a fixture" do
        for reason <- unquote(module).reason_atoms() do
          assert Map.has_key?(@fixtures, {unquote(module), reason}),
                 "missing fixture for {#{inspect(unquote(module))}, #{inspect(reason)}}"
        end
      end

      test "Exception.message/1 produces a non-empty rendered string for each reason" do
        for reason <- unquote(module).reason_atoms() do
          bindings = Map.fetch!(@fixtures, {unquote(module), reason})
          exception = unquote(module).exception(bindings)
          rendered = Exception.message(exception)

          assert is_binary(rendered),
                 "#{inspect(unquote(module))} :#{reason} → message/1 returned non-binary"

          assert rendered != "",
                 "#{inspect(unquote(module))} :#{reason} → message/1 returned empty string"

          refute String.contains?(rendered, "%Localize."),
                 "#{inspect(unquote(module))} :#{reason} → message/1 fell through to struct inspect: #{rendered}"
        end
      end
    end
  end

  describe "LocaleIntegrityError.reason_atoms/0" do
    test "lists the supported integrity failure reasons" do
      assert Localize.LocaleIntegrityError.reason_atoms() == [
               :hash_mismatch,
               :no_manifest_entry
             ]
    end
  end

  describe "LocaleDownloadError cause normalization" do
    test "a :connection_timeout cause sets the reason" do
      exception =
        Localize.LocaleDownloadError.exception(
          locale_id: :en,
          url: "http://example.com",
          cause: :connection_timeout
        )

      assert exception.reason == :connection_timeout
    end

    test "a :timeout cause maps to :request_timeout" do
      exception =
        Localize.LocaleDownloadError.exception(
          locale_id: :en,
          url: "http://example.com",
          cause: :timeout
        )

      assert exception.reason == :request_timeout
    end

    test "an :nxdomain cause sets the reason" do
      exception =
        Localize.LocaleDownloadError.exception(
          locale_id: :en,
          url: "http://example.com",
          cause: :nxdomain
        )

      assert exception.reason == :nxdomain
    end

    test "any other cause maps to :network_error" do
      exception =
        Localize.LocaleDownloadError.exception(
          locale_id: :en,
          url: "http://example.com",
          cause: {:tls_alert, :handshake_failure}
        )

      assert exception.reason == :network_error
    end
  end
end
