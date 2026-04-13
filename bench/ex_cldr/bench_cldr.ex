defmodule Bench.Cldr do
  @moduledoc """
  ex_cldr backend module used exclusively by the `:bench` environment
  to benchmark ex_cldr against Localize.

  Only built when `MIX_ENV=bench`. Keeps the providers and locale set
  intentionally minimal so the backend compiles quickly — benchmarks
  use a small representative locale set (`:en`, `:de`, `:ja`) that
  covers Latin, Continental European, and CJK shapes.
  """

  use Cldr,
    default_locale: "en",
    locales: ["en", "de", "ja"],
    providers: [Cldr.Number, Cldr.Calendar, Cldr.DateTime, Cldr.Unit],
    generate_docs: false
end
