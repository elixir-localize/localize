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
      requires: ["credo/checks/no_try_rescue.ex"],
      checks: %{
        disabled: [
          {Credo.Check.Design.AliasUsage, []}
        ],
        extra: [
          {Localize.Credo.NoTryRescue, allowed_try_after: [{Localize, :with_locale, 2}]}
        ]
      }
    }
  ]
}
