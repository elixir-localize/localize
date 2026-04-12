# Valid Elixir syntax, but does not fulfil the custom unit
# definition contract (missing :unit key, wrong types, etc.)
[
  %{name: "not_a_unit", base: "meter"},
  "just a string",
  42
]
