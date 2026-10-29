# Credo configuration for Localize.
#
# Policy decisions (July 2026):
#
# * `Design.AliasUsage` is disabled. Localize deliberately fully
#   qualifies many calls because module names such as `Localize.List`,
#   `Localize.Date`, `Localize.Time`, `Localize.DateTime`,
#   `Localize.String` and `Localize.Calendar` shadow the standard
#   library when aliased. The preferred style is to alias Localize
#   submodules opportunistically when the trailing segment does NOT
#   clash with the stdlib, and never as a bulk conversion.
#
# * `Refactor.Nesting` stays at the default maximum depth of 2:
#   multi-clause helper functions with pattern matching are preferred
#   over nested case/cond/if.
#
# * `Refactor.CyclomaticComplexity` stays at the default of 9;
#   naturally-branchy functions (format token dispatch, options
#   resolution) carry inline `credo:disable` annotations with a
#   one-line justification instead of a raised global limit.
#
# * `Refactor.Apply` stays enabled; legitimate dynamic dispatch from
#   token/handler tables is annotated inline.
#
# Policy decision (October 2026):
#
# * `Localize.Credo.ErrorTuple` (`credo/checks/error_tuple.ex`) reports
#   every error tuple built with an atom or a string by a public function
#   of `lib/`: an error is `{:error, exception}`. A site whose atom a
#   contract outside Localize requires, such as Elixir's `Calendar` parse
#   callbacks, carries an inline `credo:disable-for-next-line` with the
#   reason; `Localize.Calendar.ISO` answers the Calendrical behaviour
#   throughout and is exempt for the whole file.
#
#   It reads neither `defp` nor `data/`. An atom built in a private
#   function is a private sum type naming which rule or lookup failed,
#   and one boundary turns it into the exception the caller sees:
#   `Localize.Number.Grammar.read_with/7` answers the fifteen rules of
#   the number grammar with one `Localize.InvalidValueError`, and
#   `Localize.DateTime.Formatter`'s day-period lookups are each a reason
#   to fall back to AM/PM. `data/` is the locale generation pipeline,
#   which `mix.exs` does not ship, so its errors are read by a
#   maintainer at a terminal and have no locale to be said in.
#
# Policy decision (September 2026):
#
# * `Localize.Credo.NoTryRescue` (`credo/checks/no_try_rescue.ex`)
#   reports every `try` and every function-level `rescue`, `catch`,
#   `else` or `after`. The agreed exceptions are a `rescue` of
#   `ArgumentError` around a lone `String.to_existing_atom/1` call,
#   and the `try`/`after` of the functions listed below, whose cleanup
#   is documented behaviour. Extending the list needs its own reason.
%{
  configs: [
    %{
      name: "default",
      strict: true,
      files: %{
        included: ["lib/", "test/", "data/", "credo/"],
        excluded: ["test/support/data/"]
      },
      plugins: [{ExSlop, []}],
      requires: ["credo/checks/no_try_rescue.ex", "credo/checks/error_tuple.ex"],
      checks: %{
        disabled: [
          {Credo.Check.Design.AliasUsage, []}
        ],
        extra:
          [
            {Localize.Credo.NoTryRescue, allowed_try_after: [{Localize, :with_locale, 2}]},
            {Localize.Credo.ErrorTuple, files: %{included: ["lib/"]}}
          ] ++ Enum.map(ExSlop.recommended_checks(), &{&1, []})
      }
    }
  ]
}
