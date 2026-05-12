defmodule Localize.FormatError do
  @moduledoc """
  Exception raised when a value cannot be formatted by the requested
  message format function due to an incompatible type or missing
  configuration.

  The `:reason` field is a documented atom describing the failure
  category. The `:detail` field carries any additional human-readable
  context produced by a downstream formatter (for example, the
  `Exception.message/1` text of the formatter's own error). The
  `:cause` field carries the underlying exception when one is
  available, so callers can pattern-match on the inner type.

  """

  defexception [:value, :function, :reason, :detail, :cause]

  @type reason ::
          :unbalanced_markup
          | :mismatched_close
          | :formatter_failed
          | :downstream_failure

  @type t :: %__MODULE__{
          value: term() | nil,
          function: atom() | nil,
          reason: reason() | nil,
          detail: String.t() | nil,
          cause: Exception.t() | nil
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{reason: :unbalanced_markup, detail: nil, value: value}) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "message",
      "Cannot format {$value}: unbalanced markup: unclosed markup tag",
      value: inspect(value)
    )
  end

  def message(%__MODULE__{reason: :unbalanced_markup, detail: detail, value: value}) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "message",
      "Cannot format {$value}: unbalanced markup: {$detail}",
      value: inspect(value),
      detail: detail
    )
  end

  def message(%__MODULE__{reason: :mismatched_close, detail: detail, value: value}) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "message",
      "Cannot format {$value}: unbalanced markup: close tag {$detail} does not match open",
      value: inspect(value),
      detail: detail || "(unknown)"
    )
  end

  def message(%__MODULE__{reason: :formatter_failed, cause: cause})
      when not is_nil(cause) do
    Exception.message(cause)
  end

  def message(%__MODULE__{reason: :formatter_failed, detail: detail})
      when is_binary(detail) do
    detail
  end

  def message(%__MODULE__{reason: :downstream_failure, cause: cause})
      when not is_nil(cause) do
    Exception.message(cause)
  end

  def message(%__MODULE__{value: value, function: function, detail: detail})
      when is_binary(detail) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "message",
      "Cannot format {$value} with function {$function}: {$detail}",
      value: inspect(value),
      function: inspect(function),
      detail: detail
    )
  end

  def message(%__MODULE__{value: value, function: function}) do
    Gettext.dpgettext(
      Localize.Gettext,
      "localize",
      "message",
      "Cannot format {$value} with function {$function}",
      value: inspect(value),
      function: inspect(function)
    )
  end
end
