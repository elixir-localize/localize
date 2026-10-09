defmodule Localize.DateTimeParseLengthError do
  @moduledoc """
  Returned when text offered to the date-time parser is longer than a date
  and time can be.

  Reading a date and time means trying each place the text could divide into
  a date half and a time half, so the work grows with the square of the
  text's length: text that holds a hundred possible divisions is read a
  hundred times over. A date and time is bounded — the longest any locale
  writes, a full Dzongkha date and time with its zone named in full, is 329
  bytes — so text well beyond that is refused rather than read.

  The bound is 1,024 bytes and `:max_parse_length` raises or lowers it:

      config :localize, :max_parse_length, 4_096

  ### Fields

  * `:input_length` — the length of the text offered, in bytes.

  * `:max_length` — the bound it exceeded, in bytes.

  """

  defexception [:input_length, :max_length]

  @type t :: %__MODULE__{
          input_length: non_neg_integer() | nil,
          max_length: pos_integer() | nil
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{input_length: input_length, max_length: max_length}) do
    Localize.Exception.safe_message(
      "datetime",
      "Text of {$input_length} bytes is longer than the {$max_length} bytes a date and time is read from.",
      input_length: input_length,
      max_length: max_length
    )
  end
end
