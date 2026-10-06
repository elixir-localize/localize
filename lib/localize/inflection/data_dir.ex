defmodule Localize.Inflection.DataDir do
  @moduledoc """
  Resolves the directory holding the compiled inflection data.

  Inflection data is optional: when it has not been downloaded,
  inflection functions return
  `{:error, %Localize.InflectionDataNotAvailableError{}}` rather
  than raising. Three configuration forms are
  recognised, following the locale-cache convention (see
  `Localize.Locale.Provider.locale_cache_dir/0`):

      # 1. Recommended. Resolved as
      #    `Application.app_dir(:my_app, "priv/localize/inflection")`
      #    at every read, so it computes the right path in mix
      #    tasks and in releases.
      config :localize, otp_app: :my_app

      # 2. :otp_app plus a *relative* :inflection_data_dir,
      #    resolved against the app's runtime root.
      config :localize, otp_app: :my_app, inflection_data_dir: "priv/i18n/inflection"

      # 3. An absolute :inflection_data_dir for fully custom
      #    locations.
      config :localize, inflection_data_dir: "/var/lib/localize/inflection"

  Without configuration the directory defaults to the `localize`
  dependency's own `priv/localize/inflection`.

  ## The data version segment

  Artifacts live in a subdirectory named for
  `Localize.Inflection.Provider.data_version/0`, mirroring the CDN
  layout the same version addresses, so the configured directory
  holds one subdirectory per data version:

      priv/localize/inflection/ae92d425e57a-r3/de.etf

  The segment makes an artifact of an earlier data version
  unreachable rather than merely detectable: it is never the file a
  later version reads, so `dir/0` is empty after a version bump and
  the data downloads afresh. Recording the version *inside* each
  artifact instead, as the locale cache does in
  `Localize.Locale.Provider.Cache.stale?/1`, would mean decoding the
  file to learn whether to read it, and an inflection artifact
  reaches 11 MB where a locale file stays near 1 MB.

  """

  alias Localize.Inflection.Provider

  @default_subdir "priv/localize/inflection"

  @doc """
  Returns the configured inflection data directory, without the data
  version segment.

  This is the directory `:inflection_data_dir` and `:otp_app`
  configure. Artifacts are not written here: each data version takes
  a subdirectory of it, which `dir/0` returns.

  ### Returns

  * An absolute directory path as a string.

  ### Examples

      iex> is_binary(Localize.Inflection.DataDir.base_dir())
      true

  """
  @spec base_dir() :: String.t()
  def base_dir do
    otp_app = Application.get_env(:localize, :otp_app)
    data_dir = Application.get_env(:localize, :inflection_data_dir)

    cond do
      is_binary(data_dir) and Path.type(data_dir) == :absolute ->
        data_dir

      is_binary(data_dir) and otp_app != nil ->
        Application.app_dir(otp_app, data_dir)

      is_binary(data_dir) ->
        raise ArgumentError,
              "a relative :inflection_data_dir requires an :otp_app anchor; " <>
                "configure `config :localize, otp_app: :my_app, inflection_data_dir: #{inspect(data_dir)}`"

      otp_app != nil ->
        Application.app_dir(otp_app, @default_subdir)

      true ->
        Localize.Priv.path(Path.relative_to(@default_subdir, "priv"))
    end
  end

  @doc """
  Returns the directory holding the current data version's artifacts.

  It is `base_dir/0` joined with
  `Localize.Inflection.Provider.data_version/0`.

  ### Returns

  * An absolute directory path as a string.

  ### Examples

      iex> dir = Localize.Inflection.DataDir.dir()
      iex> String.ends_with?(dir, Localize.Inflection.Provider.data_version())
      true

  """
  @spec dir() :: String.t()
  def dir do
    Path.join(base_dir(), Provider.data_version())
  end

  @doc """
  Returns the path of a file within the current data version's
  inflection data directory.

  ### Arguments

  * `name` is a file name such as "en.etf".

  ### Returns

  * An absolute file path as a string.

  ### Examples

      iex> path = Localize.Inflection.DataDir.path("en.etf")
      iex> String.ends_with?(path, "en.etf")
      true

  """
  @spec path(String.t()) :: String.t()
  def path(name) do
    Path.join(dir(), name)
  end
end
