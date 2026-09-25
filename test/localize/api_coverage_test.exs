defmodule Localize.ApiCoverageTest do
  # Public functions and branches the rest of the suite leaves untested:
  # bang and default-argument variants, error returns for unsupported
  # input, locale-driven results and the download transport's failure
  # paths. Expected values are the library's verified output.
  #
  # async: false because the transport tests capture the log, which
  # captures whatever any test logs meanwhile.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  describe "interval and datetime parts" do
    test "interval parts concatenate to the interval string" do
      parts = Localize.Interval.to_parts!(~D[2026-05-05], ~D[2026-05-10], locale: :en)

      assert Enum.map_join(parts, & &1.value) == "May 5 – 10, 2026"
      assert Localize.Interval.to_parts(~D[2026-05-05], ~D[2026-05-10]) == {:ok, parts}
      assert Localize.Interval.to_string!(~D[2026-05-05], ~D[2026-05-10]) == "May 5 – 10, 2026"
    end

    test "interval bang variants raise the error for mismatched endpoints" do
      assert_raise Localize.DateTimeIntervalFormatError, fn ->
        Localize.Interval.to_parts!(~D[2026-05-05], ~T[10:00:00], locale: :en)
      end
    end

    test "datetime parts concatenate to the datetime string" do
      datetime = ~N[2026-05-23 10:30:00]
      parts = Localize.DateTime.to_parts!(datetime, locale: :en, format: :short)

      assert Enum.map_join(parts, & &1.value) ==
               Localize.DateTime.to_string!(datetime, locale: :en, format: :short)

      assert {:ok, [_ | _]} = Localize.DateTime.to_parts(datetime)
    end

    test "datetime parts of a map with no date or time fields raise" do
      assert_raise Localize.DateTimeInvalidInputError, fn ->
        Localize.DateTime.to_parts!(%{foo: :bar})
      end
    end
  end

  describe "unit ranges and parts" do
    test "a range of like units" do
      one_meter = Localize.Unit.new!(1, "meter")
      three_meters = Localize.Unit.new!(3, "meter")

      assert Localize.Unit.to_range_string(one_meter, three_meters, locale: :en) ==
               {:ok, "1–3 meters"}

      assert Localize.Unit.to_range_string!(
               Localize.Unit.new!(1, "kilometer"),
               Localize.Unit.new!(5, "kilometer"),
               locale: :de
             ) == "1–5 Kilometer"

      assert {:ok, parts} = Localize.Unit.to_range_parts(one_meter, three_meters, locale: :en)
      assert Enum.map_join(parts, & &1.value) == "1–3 meters"
      assert Localize.Unit.to_range_parts!(one_meter, three_meters, locale: :en) == parts
    end

    test "a range of unlike units is an error, and the bang variants raise it" do
      meter = Localize.Unit.new!(1, "meter")
      second = Localize.Unit.new!(3, "second")

      assert {:error, %Localize.InvalidValueError{}} =
               Localize.Unit.to_range_string(meter, second, locale: :en)

      assert_raise Localize.InvalidValueError, fn ->
        Localize.Unit.to_range_string!(meter, second, locale: :en)
      end

      assert_raise Localize.InvalidValueError, fn ->
        Localize.Unit.to_range_parts!(meter, second, locale: :en)
      end
    end

    test "the parts of a single unit" do
      assert Localize.Unit.to_parts(Localize.Unit.new!(3, "meter")) ==
               {:ok,
                [
                  %{type: :integer, value: "3"},
                  %{type: :literal, value: " "},
                  %{type: :unit, value: "meters"}
                ]}

      assert Localize.Unit.to_parts!(Localize.Unit.new!(3, "meter"), locale: :fr) == [
               %{type: :integer, value: "3"},
               %{type: :literal, value: " "},
               %{type: :unit, value: "mètres"}
             ]
    end
  end

  describe "relative time" do
    test "each kind of value is measured against an explicit baseline" do
      assert Localize.DateTime.Relative.to_string(~D[2026-05-20],
               relative_to: ~D[2026-05-23],
               locale: :en
             ) == {:ok, "3 days ago"}

      assert Localize.DateTime.Relative.to_string(~T[10:00:00],
               relative_to: ~T[12:00:00],
               locale: :en
             ) == {:ok, "2 hours ago"}

      assert Localize.DateTime.Relative.to_string(~N[2026-05-23 10:00:00],
               relative_to: ~N[2026-05-23 12:00:00],
               locale: :en
             ) == {:ok, "2 hours ago"}

      assert Localize.DateTime.Relative.to_string(~U[2026-05-23 10:00:00Z],
               relative_to: ~U[2026-05-23 12:00:00Z],
               locale: :en
             ) == {:ok, "2 hours ago"}
    end

    test "a baseline of another type is converted where the conversion is unambiguous" do
      for relative_to <- [~U[2026-05-23 12:00:00Z], ~N[2026-05-23 12:00:00]] do
        assert Localize.DateTime.Relative.to_string(~D[2026-05-20],
                 relative_to: relative_to,
                 locale: :en
               ) == {:ok, "3 days ago"}

        assert Localize.DateTime.Relative.to_string(~T[10:00:00],
                 relative_to: relative_to,
                 locale: :en
               ) == {:ok, "2 hours ago"}
      end

      assert Localize.DateTime.Relative.to_string(~N[2026-05-23 10:00:00],
               relative_to: ~U[2026-05-23 12:00:00Z],
               locale: :en
             ) == {:ok, "2 hours ago"}
    end

    test "a baseline that cannot be compared with the value is an error" do
      pairs = [
        {~U[2026-05-23 10:00:00Z], ~N[2026-05-23 12:00:00]},
        {~U[2026-05-23 10:00:00Z], ~D[2026-05-24]},
        {~N[2026-05-23 10:00:00], ~D[2026-05-24]},
        {~D[2026-05-20], ~T[12:00:00]},
        {~T[10:00:00], ~D[2026-05-23]},
        {~D[2026-05-20], :bogus}
      ]

      for {relative, relative_to} <- pairs do
        options = [relative_to: relative_to, locale: :en]

        assert {:error, %Localize.InvalidValueError{value: ^relative_to, context: ":relative_to"}} =
                 Localize.DateTime.Relative.to_string(relative, options)

        assert {:error, %Localize.InvalidValueError{value: ^relative_to, context: ":relative_to"}} =
                 Localize.DateTime.Relative.to_parts(relative, options)
      end
    end

    test "bang variants return the value" do
      assert Localize.DateTime.Relative.to_string!(2, unit: :hour, locale: :en) == "in 2 hours"

      assert Localize.DateTime.Relative.to_parts!(-1, unit: :month, locale: :en) ==
               [%{type: :literal, value: "last month"}]
    end

    test "an unsupported value is an error, and the bang variants raise it" do
      for relative <- [:bogus, nil, "3 days"] do
        assert {:error, %Localize.InvalidValueError{value: ^relative}} =
                 Localize.DateTime.Relative.to_string(relative, locale: :en)

        assert {:error, %Localize.InvalidValueError{value: ^relative}} =
                 Localize.DateTime.Relative.to_parts(relative, locale: :en)
      end

      assert_raise Localize.InvalidValueError, fn ->
        Localize.DateTime.Relative.to_string!(:bogus)
      end

      assert_raise Localize.InvalidValueError, fn ->
        Localize.DateTime.Relative.to_parts!(:bogus)
      end
    end

    test "options that are not a keyword list are an error" do
      assert {:error, %Localize.InvalidValueError{value: :bogus}} =
               Localize.DateTime.Relative.to_string(3, :bogus)

      assert {:error, %Localize.InvalidValueError{value: :bogus}} =
               Localize.DateTime.Relative.to_parts(3, :bogus)
    end
  end

  describe "currency bang variants" do
    test "raise the error the plain variant returns" do
      cases = [
        {fn -> Localize.Currency.currencies_for_locale("xx-invalid-!!") end,
         fn -> Localize.Currency.currencies_for_locale!("xx-invalid-!!") end},
        {fn -> Localize.Currency.currency_strings("xx-invalid-!!") end,
         fn -> Localize.Currency.currency_strings!("xx-invalid-!!") end},
        {fn -> Localize.Currency.strings_for_currency(:XYZ, :en) end,
         fn -> Localize.Currency.strings_for_currency!(:XYZ, :en) end},
        {fn -> Localize.Currency.territory_currencies(:not_a_territory) end,
         fn -> Localize.Currency.territory_currencies!(:not_a_territory) end}
      ]

      for {plain, bang} <- cases do
        assert {:error, %exception_module{}} = plain.()
        assert_raise exception_module, bang
      end
    end
  end

  describe "collation sort modules" do
    test "Insensitive ignores case and Sensitive puts lower case first" do
      assert Enum.sort(["b", "A", "a", "B"], Localize.Collation.Insensitive) == [
               "A",
               "a",
               "b",
               "B"
             ]

      assert Enum.sort(["b", "A", "a", "B"], Localize.Collation.Sensitive) == ["a", "A", "b", "B"]
    end
  end

  describe "Localize.Utils.Http against a local server" do
    setup do
      root = Path.join(System.tmp_dir!(), "localize_http_#{System.unique_integer([:positive])}")
      docroot = Path.join(root, "docroot")
      server_root = Path.join(root, "server_root")
      File.mkdir_p!(docroot)
      File.mkdir_p!(server_root)
      File.write!(Path.join(docroot, "body.txt"), String.duplicate("x", 64))

      {:ok, started} = Application.ensure_all_started(:inets)

      {:ok, httpd} =
        :inets.start(:httpd,
          port: 0,
          bind_address: ~c"127.0.0.1",
          server_name: ~c"localize_api_coverage_test",
          server_root: String.to_charlist(server_root),
          document_root: String.to_charlist(docroot),
          mime_type: ~c"text/plain"
        )

      [port: port] = :httpd.info(httpd, [:port])

      on_exit(fn ->
        :inets.stop(:httpd, httpd)
        Enum.each(started, &Application.stop/1)
        File.rm_rf(root)
      end)

      {:ok, base_url: "http://127.0.0.1:#{port}"}
    end

    test "the {url, headers} form returns the body", %{base_url: base_url} do
      assert Localize.Utils.Http.get({base_url <> "/body.txt", [{~c"accept", ~c"*/*"}]}) ==
               {:ok, String.duplicate("x", 64)}
    end

    test "a body larger than the size cap is refused", %{base_url: base_url} do
      {result, log} =
        with_log(fn -> Localize.Utils.Http.get(base_url <> "/body.txt", max_body_bytes: 16) end)

      assert result == {:error, :response_too_large}
      assert log =~ "Refusing oversized HTTP response"
    end

    test "a server that accepts but never answers times out" do
      {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
      {:ok, port} = :inet.port(listen_socket)

      holder =
        spawn(fn ->
          {:ok, _socket} = :gen_tcp.accept(listen_socket)
          Process.sleep(:infinity)
        end)

      on_exit(fn ->
        Process.exit(holder, :kill)
        :gen_tcp.close(listen_socket)
      end)

      {result, log} =
        with_log(fn ->
          Localize.Utils.Http.get("http://127.0.0.1:#{port}/slow",
            timeout: 200,
            connection_timeout: 1_000
          )
        end)

      assert result == {:error, :timeout}
      assert log =~ "Timeout downloading"
    end
  end
end
