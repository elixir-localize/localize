defmodule Localize.Message.Parsed do
  @moduledoc """
  An MF2 message that `Localize.Message.parse/2` has parsed and validated, ready to be formatted many times.

  A message formatted from a string is parsed and checked against TR35's data-model rules on every call. An application that keeps its messages as data, such as translations a site's editors write into a database, parses each once with `Localize.Message.parse/2` and passes the result to `Localize.Message.format/3`, `Localize.Message.format_to_iolist/3` or `Localize.Message.format_to_safe_list/3`, which skip both steps.

  The struct holds the message's source as well as its parsed form: the ICU backend formats from the source, and error messages quote it. Treat the fields as opaque.

  """

  @enforce_keys [:source, :ast]
  defstruct [:source, :ast]

  @typedoc "A parsed and validated MF2 message."
  @type t :: %__MODULE__{source: String.t(), ast: term()}
end
