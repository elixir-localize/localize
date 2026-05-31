defmodule Localize.LocaleCacheDirError do
  @moduledoc """
  Exception raised when the `:locale_cache_dir` or `:otp_app`
  application environment keys are misconfigured.

  Three failure modes:

  * `:relative_path` — `:locale_cache_dir` is a relative string **and**
    no `:otp_app` is configured to anchor it. A relative path with no
    anchor resolves against the BEAM's current working directory,
    which differs between `mix` tasks (CWD = project root), `mix test`,
    and a release (CWD = release root) — one value cannot be correct
    in all phases.

  * `:invalid_form` — `:locale_cache_dir` is set but is not a string.

  * `:invalid_otp_app` — `:otp_app` is set but is not an atom.

  ## Supported configurations

  Three forms are accepted:

  1. **`:otp_app` only** (recommended) — caches in
     `Application.app_dir(<otp_app>, "priv/localize/locales")`:

          config :localize, otp_app: :my_app

  2. **`:otp_app` + relative `:locale_cache_dir`** — caches in
     `Application.app_dir(<otp_app>, <relative>)`:

          config :localize,
            otp_app: :my_app,
            locale_cache_dir: "priv/i18n/cache"

  3. **Absolute `:locale_cache_dir`** — used verbatim; `:otp_app`
     is ignored:

          config :localize, locale_cache_dir: "/var/lib/localize/locales"

  `:otp_app` follows the Elixir/Phoenix/Ecto/Gettext convention.
  `Application.app_dir/2` is re-resolved at every read, so the same
  config value produces the correct path in mix tasks
  (`_build/<env>/lib/<app>/priv/...`) and in releases
  (`/path/to/release/lib/<app>-X.Y.Z/priv/...`) without per-phase
  duplication.

  """

  @behaviour Localize.Exception

  defexception [:reason, :value, :detail]

  @type reason :: :relative_path | :invalid_form | :invalid_otp_app

  @type t :: %__MODULE__{
          reason: reason() | nil,
          value: term() | nil,
          detail: String.t() | nil
        }

  @impl Localize.Exception
  def reason_atoms, do: [:relative_path, :invalid_form, :invalid_otp_app]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{reason: :relative_path, value: value}) do
    "config :localize, :locale_cache_dir was set to a relative path #{inspect(value)} " <>
      "with no :otp_app configured to anchor it. A relative path with no anchor resolves " <>
      "against the BEAM's current working directory, which differs between mix tasks " <>
      "(project root), mix test, and a release (release root) — one value cannot be " <>
      "correct in all phases. Either pair the relative path with an :otp_app anchor " <>
      "(`config :localize, otp_app: :your_otp_app, locale_cache_dir: #{inspect(value)}`), " <>
      "use :otp_app on its own for the default `priv/localize/locales/` subpath, or " <>
      "supply an absolute path string for `:locale_cache_dir`."
  end

  def message(%__MODULE__{reason: :invalid_form, value: value}) do
    "config :localize, :locale_cache_dir must be a path string (absolute, or relative " <>
      "when paired with :otp_app), got #{inspect(value)}. For app-resolved paths, use " <>
      "`config :localize, otp_app: :your_otp_app`."
  end

  def message(%__MODULE__{reason: :invalid_otp_app, value: value}) do
    "config :localize, :otp_app must be an atom naming the consumer application, " <>
      "got #{inspect(value)}."
  end
end
