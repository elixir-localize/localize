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
%{
  configs: [
    %{
      name: "default",
      strict: true,
      files: %{
        included: ["lib/", "test/", "data/"],
        excluded: ["test/support/data/"]
      },
      checks: %{
        disabled: [
          {Credo.Check.Design.AliasUsage, []}
        ]
      }
    }
  ]
}
