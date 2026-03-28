defmodule Localize.MixProject do
  use Mix.Project

  @version "0.1.0"
  @cldr_version_path "priv/localize/version"

  def project do
    [
      app: :localize,
      version: @version,
      cldr_version: cldr_version(),
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: maybe_elixir_make() ++ [:yecc, :leex] ++ Mix.compilers(),
      make_makefile: "c_src/Makefile",
      deps: deps(),
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

  def cldr_version do
    @cldr_version_path
    |> File.read!()
    |> String.trim()
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Localize.Application, []}
    ]
  end

  defp elixirc_paths(:dev), do: ["lib", "data"]
  defp elixirc_paths(:test), do: ["lib", "data", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:decimal, "~> 2.0"},
      {:gettext, "~> 1.0"},
      {:unicode, "~> 1.21"},
      {:nimble_parsec, "~> 1.0", runtime: false},
      {:elixir_make, "~> 0.4", runtime: false, optional: true},
      {:sweet_xml, "~> 0.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false},
      {:stream_data, "~> 1.0", only: :test}
      ] ++ maybe_json_polyfill()
  end

  def maybe_json_polyfill do
    if Code.ensure_loaded?(:json) do
      []
    else
      [{:json_polyfill, "~> 0.2 or 1.0"}]
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
    String.downcase(System.get_env("LOCALIZE_NIF", "false")) == "true" or
      Application.get_env(:localize, :nif, false) == true
  end
end
