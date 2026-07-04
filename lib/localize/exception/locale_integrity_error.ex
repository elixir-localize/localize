defmodule Localize.LocaleIntegrityError do
  @moduledoc """
  Exception raised when a downloaded locale file fails integrity
  verification against the hash manifest bundled with the package.

  """

  @behaviour Localize.Exception

  defexception [:locale_id, :url, :reason, :expected, :actual]

  @type reason :: :hash_mismatch | :no_manifest_entry

  @type t :: %__MODULE__{
          locale_id: atom(),
          url: String.t() | nil,
          reason: reason(),
          expected: String.t() | nil,
          actual: String.t() | nil
        }

  @impl Localize.Exception
  def reason_atoms, do: [:hash_mismatch, :no_manifest_entry]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{reason: :no_manifest_entry, locale_id: locale_id, url: url}) do
    Localize.Exception.safe_message(
      "locale",
      "The locale {$locale_id} downloaded from {$url} has no entry in the locale hash manifest.",
      locale_id: inspect(locale_id),
      url: url
    )
  end

  def message(%__MODULE__{
        reason: :hash_mismatch,
        locale_id: locale_id,
        url: url,
        expected: expected,
        actual: actual
      }) do
    Localize.Exception.safe_message(
      "locale",
      "The locale {$locale_id} downloaded from {$url} failed integrity verification. Expected SHA-256 {$expected} but the content hashes to {$actual}.",
      locale_id: inspect(locale_id),
      url: url,
      expected: expected,
      actual: actual
    )
  end
end
