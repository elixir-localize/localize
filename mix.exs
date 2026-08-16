defmodule Localize.MixProject do
  use Mix.Project

  @version "1.2.0"
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
      test_coverage: [ignore_modules: coverage_ignore_modules()],
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

  # Packaging runs in `:release` so that `elixirc_paths/1` resolves to
  # `["lib"]` alone. In `:dev` it also compiles `data/`, the locale-data
  # generation pipeline, which is build tooling rather than part of the
  # package. Declaring the environment here means the tarball is built
  # the same way whether or not `MIX_ENV=release` is typed on the
  # command line — `mix hex.publish` is enough.
  def cli do
    [
      preferred_envs: [
        "hex.build": :release,
        "hex.publish": :release
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
      # Apache-2.0 covers the library; Unicode-3.0 covers the CLDR and UCD
      # data compiled into `priv/localize/` and downloaded from the locale
      # CDN. See the "Unicode Data" section of LICENSE.md.
      licenses: ["Apache-2.0", "Unicode-3.0"],
      links: links(),
      files: [
        "lib",
        "src/*.xrl",
        "src/*.yrl",
        "mix.exs",
        "README*",
        "CHANGELOG*",
        "LICENSE*",
        "usage-rules.md",
        # NIF sources so `LOCALIZE_NIF=true` builds from the hex package.
        # The vendored ICU headers under c_src/platform are not needed —
        # the Makefile locates ICU via pkg-config or Homebrew.
        "c_src/Makefile",
        "c_src/env.mk",
        "c_src/*.cpp",
        "priv/localize/*.etf",
        "priv/localize/version",
        "priv/localize/localize_patch_version",
        "priv/localize/supplemental_data",
        "priv/localize/validity",
        "priv/localize/locales/en.etf",
        "priv/localize/locales/und.etf"
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
        ] ++ Path.wildcard("guides/*.md") ++ cheatsheet_extras(),
      formatters: ["html", "markdown"],
      groups_for_modules: groups_for_modules(),
      groups_for_extras: groups_for_extras(),
      skip_undefined_reference_warnings_on:
        [
          "CHANGELOG.md"
        ] ++ Path.wildcard("guides/*.md") ++ Path.wildcard("cheatsheets/*.md")
    ]
  end

  # Cheatsheets share basenames with guides (e.g. `collation.md`), which
  # would make ex_doc emit unstable, suffixed page names such as
  # `collation-1.html`. Giving each cheatsheet an explicit `:filename`
  # keeps the guide URLs stable (`collation.html`) and the cheatsheet
  # URLs predictable (`collation_cheatsheet.html`).
  defp cheatsheet_extras do
    for path <- Path.wildcard("cheatsheets/*.md") do
      {path, filename: Path.basename(path, ".md") <> "_cheatsheet"}
    end
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
      Application: ~r/^(Localize\.Supervisor$|Mix\.Tasks\.Localize)/,
      Exceptions: ~r/^Localize\.(\w+Error|Exception)$/
    ]
  end

  defp groups_for_extras do
    [
      Guides: [
        "guides/ecosystem.md",
        "guides/number_formatting.md",
        "guides/plural_rules.md",
        "guides/date_time_formatting.md",
        "guides/interval_and_duration_formatting.md",
        "guides/unit_formatting.md",
        "guides/list_formatting.md",
        "guides/message_formatting.md",
        "guides/locale_validation.md",
        "guides/display_names.md",
        "guides/collation.md"
      ],
      Advanced: [
        "guides/architecture.md",
        "guides/supervision.md",
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

  # Modules excluded from `mix test --cover` measurement so the
  # coverage number reflects the runtime library, not build tooling:
  #
  # * `Localize.Data.*` — the locale-data generation pipeline, run by
  #   `mix localize.generate_locales`, never at library runtime.
  #
  # * `Mix.Tasks.*` — mix tasks.
  #
  # * Compile-time-only modules — macros, parser generators and
  #   loaders that execute during compilation, which the coverage
  #   tool cannot observe.
  #
  # * `:leex`/`:yecc` generated lexers and parsers — generated code.
  #
  # * Test-support modules under `test/support` — test harness code.
  defp coverage_ignore_modules do
    [
      ~r/^Localize\.Data(\.|$)/,
      ~r/^Mix\.Tasks\./,
      GenerateNumber,
      Localize.DateTime.TestData,
      Localize.LocaleDisplayNameGenerator,
      Localize.Test.PreferenceData,
      Localize.DateTime.Timezone.Builder,
      Localize.Macros,
      Localize.Gettext.Messages,
      Localize.Message.Parser.Combinator,
      Localize.Unit.Parser.Combinator,
      Localize.Rfc5646.Grammar,
      Localizer.Rfc5646.Core,
      Localize.Number.PluralRule.Loader,
      Localize.Number.PluralRule.Transformer,
      :localize_rbnf_lexer,
      :localize_rbnf_parser,
      :localize_plural_rules_lexer,
      :localize_plural_rules_parser,
      :localize_decimal_formats_lexer,
      :localize_decimal_formats_parser,
      :localize_date_time_format_lexer
    ]
  end

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
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.0", only: :test}
    ] ++ maybe_json_polyfill() ++ maybe_cldr()
  end

  # json_polyfill (the EEP 68 :json module for OTP 26) is provided for
  # THIS project's own dev/test/CI only — `only:` dependencies never
  # enter the hex package requirements, so which machine publishes is
  # irrelevant. It is deliberately NOT a package dependency: OTP 26
  # consumers add {:json_polyfill, "~> 0.2 or ~> 1.0"} to their own
  # deps (see README) and the supervisor raises with instructions at
  # application start when :json is missing. The conditional avoids
  # fetching it on OTP >= 27, where :json is built in and the
  # polyfill's own build fails.
  defp maybe_json_polyfill do
    if Code.ensure_loaded?(:json) do
      []
    else
      [{:json_polyfill, "~> 0.2 or ~> 1.0", only: [:dev, :test]}]
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
