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

  @behaviour Localize.Exception

  defexception [:value, :function, :reason, :detail, :cause]

  @type reason ::
          :unbalanced_markup
          | :mismatched_close
          | :formatter_failed
          | :downstream_failure
          | :duplicate_declaration
          | :duplicate_option_name
          | :duplicate_variant
          | :missing_selector_annotation
          | :variant_key_mismatch
          | :missing_fallback_variant
          | :unknown_function

  @type t :: %__MODULE__{
          value: term() | nil,
          function: atom() | nil,
          reason: reason() | nil,
          detail: String.t() | nil,
          cause: Exception.t() | nil
        }

  @impl Localize.Exception
  def reason_atoms,
    do: [
      :unbalanced_markup,
      :mismatched_close,
      :formatter_failed,
      :downstream_failure,
      :duplicate_declaration,
      :duplicate_option_name,
      :duplicate_variant,
      :missing_selector_annotation,
      :variant_key_mismatch,
      :missing_fallback_variant,
      :unknown_function
    ]

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{reason: :unbalanced_markup, detail: nil, value: value}) do
    Localize.Exception.safe_message(
      "message",
      "Cannot format {$value}: unbalanced markup: unclosed markup tag",
      value: inspect(value)
    )
  end

  def message(%__MODULE__{reason: :unbalanced_markup, detail: detail, value: value}) do
    Localize.Exception.safe_message(
      "message",
      "Cannot format {$value}: unbalanced markup: {$detail}",
      value: inspect(value),
      detail: detail
    )
  end

  def message(%__MODULE__{reason: :mismatched_close, detail: detail, value: value}) do
    Localize.Exception.safe_message(
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

  def message(%__MODULE__{reason: :duplicate_declaration, detail: detail}) do
    Localize.Exception.safe_message(
      "message",
      "Invalid message: the variable {$detail} is declared more than once",
      detail: detail || "(unknown)"
    )
  end

  def message(%__MODULE__{reason: :duplicate_option_name, detail: detail}) do
    Localize.Exception.safe_message(
      "message",
      "Invalid message: the option {$detail} appears more than once in the same expression",
      detail: detail || "(unknown)"
    )
  end

  def message(%__MODULE__{reason: :missing_selector_annotation, detail: detail}) do
    Localize.Exception.safe_message(
      "message",
      "Invalid message: the selector {$detail} has no annotation; declare it with a function, as in .input {$detail :number}",
      detail: detail || "(unknown)"
    )
  end

  def message(%__MODULE__{reason: :variant_key_mismatch, detail: detail}) do
    Localize.Exception.safe_message(
      "message",
      "Invalid message: the variant with keys {$detail} does not have one key per selector",
      detail: detail || "(unknown)"
    )
  end

  def message(%__MODULE__{reason: :missing_fallback_variant, detail: _detail}) do
    Localize.Exception.safe_message(
      "message",
      "Invalid message: no variant has only catch-all keys; add a variant whose keys are all *"
    )
  end

  def message(%__MODULE__{reason: :duplicate_variant, detail: detail}) do
    Localize.Exception.safe_message(
      "message",
      "Invalid message: more than one variant has the keys {$detail}",
      detail: detail || "(unknown)"
    )
  end

  def message(%__MODULE__{reason: :unknown_function, detail: detail}) do
    Localize.Exception.safe_message(
      "message",
      "Cannot format message: unknown function {$detail}",
      detail: detail || "(unknown)"
    )
  end

  def message(%__MODULE__{value: value, function: function, detail: detail})
      when is_binary(detail) do
    Localize.Exception.safe_message(
      "message",
      "Cannot format {$value} with function {$function}: {$detail}",
      value: inspect(value),
      function: inspect(function),
      detail: detail
    )
  end

  def message(%__MODULE__{value: value, function: function}) do
    Localize.Exception.safe_message(
      "message",
      "Cannot format {$value} with function {$function}",
      value: inspect(value),
      function: inspect(function)
    )
  end
end
