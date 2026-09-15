% Tokenizes CLDR decimal formats which are described at
% http://unicode.org/reports/tr35/tr35-numbers.html#Number_Format_Patterns

Definitions.

% A number must consume at least one character. A rule that can match the
% empty string makes leex emit empty tokens at an unmatchable character
% without advancing, which loops and allocates without bound.
Number                = [@#,]+([0-9,]+)?(\.[0-9#,]+)?([Ee](\+)?[0-9]+)?|[0-9,]+(\.[0-9#,]+)?([Ee](\+)?[0-9]+)?|\.[0-9#,]+([Ee](\+)?[0-9]+)?
Percent               = %
Permille              = ‰
Plus                  = \+
Minus                 = \-
Semicolon             = ;
Currency              = ¤+
Pad                   = \*.
Quoted                = \'.\'
QuotedString          = \'([^\']|\'\')+\'
Quote                 = \'\'
Literal               = [^*@#0-9¤\+\-;%\']+

Rules.

{Number}              : {token,{format,TokenLine,TokenChars}}.
{Percent}             : {token,{percent,TokenLine,TokenChars}}.
{Permille}            : {token,{permille,TokenLine,TokenChars}}.
{Plus}                : {token,{plus,TokenLine,TokenChars}}.
{Minus}               : {token,{minus,TokenLine,TokenChars}}.
{Semicolon}           : {token,{semicolon,TokenLine,TokenChars}}.
{Currency}            : {token,{currency,TokenLine,length(TokenChars)}}.
{Pad}                 : {token,{pad,TokenLine,[lists:nth(2,TokenChars)]}}.
{Quoted}              : {token,{quoted_char,TokenLine,[lists:nth(2, TokenChars)]}}.
{QuotedString}        : {token,{literal,TokenLine,unquote(TokenChars)}}.
{Quote}               : {token,{quote,TokenLine,["'"]}}.
{Literal}             : {token,{literal,TokenLine,TokenChars}}.

Erlang code.

% A currency token carries the width of its run of currency signs, which the
% formatter resolves. Naming the token after its width would create an atom
% for every width an untrusted pattern uses.

% TR35: single quotes enclose literal text, and inside a quoted string two
% single quotes stand for one. A single quoted character is matched by the
% Quoted rule, which is listed first.
unquote(Chars) ->
  Inner = lists:sublist(Chars, 2, length(Chars) - 2),
  lists:flatten(string:replace(Inner, "''", "'", all)).