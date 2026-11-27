# TR35's RBNF rule selection rolls back from a rule with two substitutions, ICU from one with one

All references are to CLDR `6198cae999ceb4847b25ddc0815835f07fced411`.

TR35's rule selection has "If that rule has two substitutions, its base value is not an even multiple of its divisor, and the number *is* an even multiple of the rule's divisor, use the rule that precedes it in the rule list". ICU rolls back from a rule that has a remainder substitution whether or not it has a second one (`NFRule.shouldRollBack`). No number a rule set of CLDR 49 is given tells the two apart: of the 339 rules with a remainder substitution and no other whose base value is no multiple of their divisor, two hold a multiple of it, the last rules of root's `%%cyrillic-lower-final` and `%%hebrew-0-99`, which are never given 100.
