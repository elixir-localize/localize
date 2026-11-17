defmodule Localize.Gettext.Interpolation.Plain do
  @moduledoc false

  # The Gettext interpolation for Localize's own messages: its exception
  # messages and Mix task output, which are developer-facing English text.
  # It formats as `Localize.Gettext.Interpolation` does but with
  # `bidi: :none`, so they carry no bidi isolates; applications' messages
  # keep TR35's Default Bidi Strategy.

  @behaviour Gettext.Interpolation

  @format_options [bidi: :none]

  @impl Gettext.Interpolation
  def runtime_interpolate(message, bindings) when is_binary(message) do
    Localize.Gettext.Interpolation.interpolate(message, bindings, @format_options)
  end

  @impl Gettext.Interpolation
  defmacro compile_interpolate(_translation_type, message, bindings) do
    Localize.Gettext.Interpolation.__compile_interpolate__(
      message,
      bindings,
      __CALLER__,
      bidi: :none
    )
  end

  @impl Gettext.Interpolation
  def message_format do
    "icu-format"
  end
end
