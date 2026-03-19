defmodule Localize.MixProject do
  use Mix.Project

  def project do
    [
      app: :localize,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      compilers: maybe_elixir_make() ++ Mix.compilers(),
      make_makefile: "c_src/Makefile",
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_cldr, path: "../cldr"},
      {:decimal, "~> 2.0"},
      {:nimble_parsec, "~> 1.0"},
      {:sweet_xml, "~> 0.7"},
      {:elixir_make, "~> 0.4", runtime: false, optional: true}
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
