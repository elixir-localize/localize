defmodule Localize.NoParentError do
  @moduledoc false

  defexception [:message]

  def exception(message) do
    %__MODULE__{message: message}
  end
end
