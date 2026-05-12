defmodule Localize.LocaleDownloadError do
  @moduledoc """
  Exception raised when a locale file cannot be downloaded from
  its remote URL.

  """

  @behaviour Localize.Exception

  defexception [:locale_id, :url, :reason, :http_status, :cause]

  @type reason ::
          :not_modified
          | :http_error
          | :connection_timeout
          | :request_timeout
          | :nxdomain
          | :network_error
          | :safe_decode_failed
          | :stale_version

  @type t :: %__MODULE__{
          locale_id: atom(),
          url: String.t() | nil,
          reason: reason() | nil,
          http_status: 100..599 | nil,
          cause: term() | nil
        }

  @impl Localize.Exception
  def reason_atoms,
    do: [
      :not_modified,
      :http_error,
      :connection_timeout,
      :request_timeout,
      :nxdomain,
      :network_error,
      :safe_decode_failed,
      :stale_version
    ]

  @impl true
  def exception(bindings) when is_list(bindings) do
    bindings = normalize_bindings(bindings)
    struct!(__MODULE__, bindings)
  end

  defp normalize_bindings(bindings) do
    case Keyword.fetch(bindings, :reason) do
      {:ok, reason} when is_atom(reason) and not is_nil(reason) ->
        bindings

      _ ->
        case Keyword.get(bindings, :cause) do
          status when is_integer(status) ->
            Keyword.merge(bindings, reason: :http_error, http_status: status)

          :connection_timeout ->
            Keyword.put(bindings, :reason, :connection_timeout)

          :timeout ->
            Keyword.put(bindings, :reason, :request_timeout)

          :nxdomain ->
            Keyword.put(bindings, :reason, :nxdomain)

          _ ->
            Keyword.put_new(bindings, :reason, :network_error)
        end
    end
  end

  @impl true
  def message(%__MODULE__{reason: :not_modified, locale_id: locale_id, url: url}) do
    Localize.Exception.safe_message(
      "locale",
      "The locale {$locale_id} at {$url} is unchanged since the last download.",
      locale_id: inspect(locale_id),
      url: url
    )
  end

  def message(%__MODULE__{
        reason: :http_error,
        locale_id: locale_id,
        url: url,
        http_status: status
      }) do
    Localize.Exception.safe_message(
      "locale",
      "The locale {$locale_id} could not be downloaded from {$url}: HTTP {$status}.",
      locale_id: inspect(locale_id),
      url: url,
      status: status
    )
  end

  def message(%__MODULE__{reason: :connection_timeout, locale_id: locale_id, url: url}) do
    Localize.Exception.safe_message(
      "locale",
      "The locale {$locale_id} could not be downloaded from {$url}: connection timed out.",
      locale_id: inspect(locale_id),
      url: url
    )
  end

  def message(%__MODULE__{reason: :request_timeout, locale_id: locale_id, url: url}) do
    Localize.Exception.safe_message(
      "locale",
      "The locale {$locale_id} could not be downloaded from {$url}: request timed out.",
      locale_id: inspect(locale_id),
      url: url
    )
  end

  def message(%__MODULE__{reason: :nxdomain, locale_id: locale_id, url: url}) do
    Localize.Exception.safe_message(
      "locale",
      "The locale {$locale_id} could not be downloaded from {$url}: host could not be resolved.",
      locale_id: inspect(locale_id),
      url: url
    )
  end

  def message(%__MODULE__{reason: :network_error, locale_id: locale_id, url: url, cause: cause}) do
    Localize.Exception.safe_message(
      "locale",
      "The locale {$locale_id} could not be downloaded from {$url}: {$reason}.",
      locale_id: inspect(locale_id),
      url: url,
      reason: inspect(cause)
    )
  end

  def message(%__MODULE__{reason: :safe_decode_failed, locale_id: locale_id, url: url}) do
    Localize.Exception.safe_message(
      "locale",
      "The locale {$locale_id} was downloaded from {$url} but failed safe decoding.",
      locale_id: inspect(locale_id),
      url: url
    )
  end

  def message(%__MODULE__{reason: :stale_version, locale_id: locale_id, url: url}) do
    Localize.Exception.safe_message(
      "locale",
      "The locale {$locale_id} downloaded from {$url} does not match the expected version.",
      locale_id: inspect(locale_id),
      url: url
    )
  end

  def message(%__MODULE__{locale_id: locale_id, url: url, cause: cause}) do
    Localize.Exception.safe_message(
      "locale",
      "The locale {$locale_id} could not be downloaded from {$url}: {$reason}.",
      locale_id: inspect(locale_id),
      url: url,
      reason: inspect(cause)
    )
  end
end
