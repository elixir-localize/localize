defmodule Localize.Inflection.DataDir do
  @moduledoc """
  Resolves the directory holding the compiled inflection data.

  Inflection data is optional: when it has not been downloaded,
  inflection functions return `{:error, {:data_not_available,
  locale}}` rather than raising. Three configuration forms are
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

  """

  @default_subdir "priv/localize/inflection"

  @doc """
  Returns the configured inflection data directory.

  ### Returns

  * An absolute directory path as a string.

  ### Examples

      iex> is_binary(Localize.Inflection.DataDir.dir())
      true

  """
  def dir do
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
        Application.app_dir(:localize, @default_subdir)
    end
  end

  @doc """
  Returns the path of a file within the inflection data directory.

  ### Arguments

  * `name` is a file name such as "en.etf".

  ### Returns

  * An absolute file path as a string.

  """
  def path(name) do
    Path.join(dir(), name)
  end
end
