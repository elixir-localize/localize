defmodule Localize.Gettext do
  @moduledoc """
  Gettext backend for the Localize library.

  Provides localized error messages for exceptions using
  the GNU Gettext internationalization framework. Messages
  use the `"localize"` domain and are organized by context
  (`msgctxt`) corresponding to the module area: `"language_tag"`,
  `"locale"`, `"unit"`, `"datetime"`, `"currency"`.

  """

  use Gettext.Backend,
    otp_app: :localize,
    interpolation: Localize.Gettext.Interpolation
end
