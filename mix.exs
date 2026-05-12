defmodule Localize.MixProject do
  use Mix.Project

  @version "0.31.0"
  @cldr_version_path "priv/localize/version"
  @localize_patch_version_path "priv/localize/localize_patch_version"

  def project do
    [
      app: :localize,
      version: @version,
      name: "Localize",
      source_url: "https://github.com/elixir-localize/localize",
      docs: docs(),
      deps: deps(),
      description: description(),
      package: package(),
      cldr_version: cldr_version(),
      cldr_patch_version: cldr_patch_version(),
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: maybe_elixir_make() ++ [:yecc, :leex] ++ Mix.compilers(),
      make_makefile: "c_src/Makefile",
      dialyzer: [
        plt_add_apps: ~w(gettext inets mix sweet_xml nimble_parsec)a,
        ignore_warnings: ".dialyzer_ignore.exs",
        flags: [
          :error_handling,
          :unknown,
          :underspecs,
          :extra_return,
          :missing_return
        ]
      ]
    ]
  end

  def description do
    "Localization (parsing, formatting) of numbers, dates/time/calendar, units of measure, " <>
      "messages and lists. Includes localized collation."
  end

  def package do
    [
      maintainers: ["Kip Cole"],
      licenses: ["Apache-2.0"],
      links: links(),
      files: [
        "lib",
        "src/*xrl",
        "src/*.yrl",
        "mix.exs",
        "README*",
        "CHANGELOG*",
        "LICENSE*",
        "usage-rules.md",
        "priv/localize/*.etf",
        "priv/localize/version",
        "priv/localize/localize_patch_version",
        "priv/localize/supplemental_data",
        "priv/localize/validity",
        "priv/localize/locales/en.etf",
        "priv/localize/locales/und.etf",
        "priv/localize/collation_table.etf"
      ]
    ]
  end

  def links do
    %{
      "GitHub" => "https://github.com/elixir-localize/localize",
      "Readme" => "https://github.com/elixir-localize/localize/blob/v#{@version}/README.md",
      "Changelog" => "https://github.com/elixir-localize/localize/blob/v#{@version}/CHANGELOG.md"
    }
  end

  def docs do
    [
      source_ref: "v#{@version}",
      main: "readme",
      logo: "logo.png",
      extras:
        [
          "README.md",
          "LICENSE.md",
          "CHANGELOG.md"
        ] ++ Path.wildcard("guides/*.md") ++ Path.wildcard("cheatsheets/*.md"),
      formatters: ["html", "markdown"],
      groups_for_modules: groups_for_modules(),
      groups_for_extras: groups_for_extras(),
      skip_undefined_reference_warnings_on:
        [
          "CHANGELOG.md"
        ] ++ Path.wildcard("guides/*.md") ++ Path.wildcard("cheatsheets/*.md")
    ]
  end

  def groups_for_modules do
    [
      # Catches `Localize.Chars` and all its `defimpl` modules
      # (e.g. `Localize.Chars.Integer`, `Localize.Chars.Localize.Currency`).
      # Placed first so the impl modules are routed here instead of
      # being absorbed by the per-domain groups below (e.g.
      # `Localize.Chars.Localize.Currency` would otherwise match the
      # `Currencies` group's regex).
      Protocols: ~r/^Localize\.Chars(\.|$)/,
      Numbers: ~r/Localize.Number/,
      "Dates and Times": ~r/^Localize\.(Date|Time|Interval|Duration)(?!\w*Error)/,
      Locale: ~r/Localize\.Locale(?!\w*Error)/,
      "Language Tag": ~r/Localize\.(LanguageTag|Rfc5646)(?!\w*Error)/,
      Calendars: ~r/Localize.Calendar(?!\w*Error)/,
      Currencies: ~r/Localize.Currency(?!\w*Error)/,
      Languages: ~r/Localize.Language(?!\w*Error)/,
      Territories: ~r/Localize.Territory(?!\w*Error)/,
      Scripts: ~r/Localize.Script(?!\w*Error)/,
      "Units of Measure": ~r/^Localize\.Unit?(?:\.|$)/,
      Messages: ~r/Localize.Message(?!\w*Error)/,
      Gettext: ~r/Gettext(?!\w*Error)/,
      Lists: ~r/Localize.List(?!\w*Error)/,
      Collation: ~r/Localize.Collation(?!\w*Error)/,
      Utilities: ~r/Localize.Util(?!\w*Error)/,
      NIF: ~r/Localize.Nif(?!\w*Error)/,
      Exceptions: ~r/^Localize\.\w+Error$/
    ]
  end

  defp groups_for_extras do
    [
      Guides: [
        "guides/number_formatting.md",
        "guides/date_time_formatting.md",
        "guides/interval_and_duration_formatting.md",
        "guides/unit_formatting.md",
        "guides/message_formatting.md",
        "guides/collation.md"
      ],
      Advanced: [
        "guides/architecture.md",
        "guides/conformance.md",
        "guides/performance.md"
      ],
      "Migration from ex_cldr": [
        "guides/migration.md",
        "guides/performance_comparison.md"
      ],
      Cheatsheets: [
        "cheatsheets/number_formatting.md",
        "cheatsheets/date_time_formatting.md",
        "cheatsheets/unit_formatting.md",
        "cheatsheets/collation.md"
      ]
    ]
  end

  def cldr_version do
    @cldr_version_path
    |> File.read!()
    |> String.trim()
  end

  def cldr_patch_version do
    current_cldr = cldr_version()

    case File.read(@localize_patch_version_path) do
      {:ok, content} ->
        case String.trim(content) |> String.split(":", parts: 2) do
          [^current_cldr, patch] -> patch
          _other -> "0"
        end

      {:error, _} ->
        "0"
    end
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Localize.Application, []},
      extra_applications: extra_applications(Mix.env())
    ]
  end

  def extra_applications(:dev) do
    [:logger, :inets, :ssl, :observer, :wx]
  end

  def extra_applications(:bench) do
    [:logger, :inets, :ssl]
  end

  def extra_applications(_) do
    [:logger, :inets, :ssl]
  end

  defp elixirc_paths(:dev), do: ["lib", "data"]
  defp elixirc_paths(:test), do: ["lib", "data", "test/support"]
  defp elixirc_paths(:bench), do: ["lib", "ex_cldr"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:decimal, "~> 2.0 or ~> 3.0"},
      {:gettext, "~> 1.0"},
      {:ex_doc, "~> 0.18", only: [:dev, :release]},
      {:nimble_parsec, "~> 1.0", runtime: false},
      {:elixir_make, "~> 0.4", runtime: false, optional: true},
      {:sweet_xml, "~> 0.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false},
      {:stream_data, "~> 1.0", only: :test}
    ] ++ maybe_json_polyfill() ++ maybe_cldr()
  end

  defp maybe_json_polyfill do
    if Code.ensure_loaded?(:json) do
      []
    else
      [{:json_polyfill, "~> 0.2 or ~> 1.0"}]
    end
  end

  defp maybe_cldr do
    if Mix.env() == :bench do
      [
        # Benchmark-only deps — used by the `:bench` environment to
        # compare Localize with the ex_cldr_* libraries. These are
        # never compiled into any non-benchmark build.
        {:ex_cldr_numbers, "~> 2.0", only: :bench},
        {:ex_cldr_dates_times, "~> 2.0", only: :bench},
        {:ex_cldr_units, "~> 3.0", only: :bench},
        {:benchee, "~> 1.3", only: :bench}
      ]
    else
      []
    end
  end

  # Only add the :elixir_make compiler when the NIF build is opted-in
  # via the LOCALIZE_NIF=true environment variable or by setting
  # `config :localize, :nif, true` in config.exs.
  defp maybe_elixir_make do
    if nif_enabled?() do
      [:elixir_make]
    else
      []
    end
  end

  defp nif_enabled? do
    String.downcase(System.get_env("LOCALIZE_NIF", "false")) == "true" ||
      Application.get_env(:localize, :nif, false) == true
  end
end
