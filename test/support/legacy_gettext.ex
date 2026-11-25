defmodule Localize.Test.LegacyGettext do
  @moduledoc false

  # A backend with MF2 interpolation whose `errors` domain holds Ecto's
  # validation messages, translated in Gettext's own `%{name}` syntax.
  use Gettext.Backend,
    otp_app: :localize,
    priv: "test/support/fixtures/legacy_gettext",
    interpolation: Localize.Gettext.Interpolation
end
