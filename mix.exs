defmodule Localize.MixProject do
  use Mix.Project

  def project do
    [
      app: :localize,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: maybe_elixir_make() ++ [:yecc, :leex] ++ Mix.compilers(),
      make_makefile: "c_src/Makefile",
      deps: deps(),
      dialyzer: [
        ignore_warnings: ".dialyzer_ignore.exs"
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Localize.Application, []}
    ]
  end

  defp elixirc_paths(:dev), do: ["lib"]
  defp elixirc_paths(:test), do: ["lib", "test/support"]
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
    ]
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
