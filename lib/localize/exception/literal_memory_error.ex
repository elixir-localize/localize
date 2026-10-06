defmodule Localize.LiteralMemoryError do
  @moduledoc """
  Exception raised when data cannot be kept because the VM's literal memory has no room for it.

  The VM keeps the terms of `:persistent_term`, where Localize keeps each loaded locale, in its literal area, whose size is fixed when the VM starts: a gigabyte by default on a 64-bit VM. A term the area cannot take stops the VM, so Localize does not keep one the VM reports no room for. `:what` describes the data, `:needed` is its size in bytes and `:free` the bytes the VM reports free in the area.

  A VM started with a larger literal area holds more: `+MIscs 2048` is two gigabytes, the size being in megabytes.

  """

  defexception [:what, :needed, :free]

  @type t :: %__MODULE__{
          what: String.t(),
          needed: non_neg_integer(),
          free: non_neg_integer()
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{what: what, needed: needed, free: free}) do
    Localize.Exception.safe_message(
      "locale",
      "The VM's literal memory cannot hold {$what}: it needs {$needed} bytes and {$free} are free. " <>
        "Start the VM with a larger literal area, `+MIscs` and its size in megabytes, " <>
        "of which the default is 1024.",
      what: what,
      needed: Integer.to_string(needed),
      free: Integer.to_string(free)
    )
  end
end
