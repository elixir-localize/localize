-file("src/plural_rules_parser.yrl", 0).
-module(plural_rules_parser).
-file("src/plural_rules_parser.erl", 3).
-export([parse/1, parse_and_scan/1, format_error/1]).
-file("src/plural_rules_parser.yrl", 89).

-export([kernel_context/0]).

% mod function will calculate the modulo in Java fashion
% for floats and decimals so that mod(4.3, 3) == 1.3
% The function itself is defined in Cldr.Math
mod(Operand, Value) ->
  {'mod', kernel_context(), [operand(Operand), Value]}.

% Return a reference to an operand
operand(Operand) ->
  {atomize(Operand), [], 'Elixir'}.

% 'and' function
and_function(A, B) ->
  {'and', kernel_context(), [A, B]}.

% 'or' function
or_function(A, B) ->
  {'or', kernel_context(), [A, B]}.

% 'not' function
not_function(A) ->
  {'!', kernel_context(), [A]}.

% Range syntax
range(Start, End) ->
  {'..', kernel_context(), [Start, End]}.

% Inclusion forms
% -> for a range. call a helper function `within`
% so we can handle integers and floats/decimals
% separately
conditional(equals, A, B = {'..', _C, [_From, _To]}) ->
  {'within', kernel_context(), [A, B]};

% -> for an expression
% NOTE this will calculate the expression each time which is
% inefficient.  But parser isn't the right place to unwrap that.

% NOTE REMOVED DUE TO DIALYZER ERROR saying this can never match.
% tests still pass without it.
% conditional({'mod', [_C], [{_L}]}, A, B) ->
%  {'==', kernel_context(), [A, B]};

% -> for a value
conditional(equals, A, B) ->
  {'==', kernel_context(), [A, B]}.

% Convert a range list into a postfix 'or' form
% Just two items in the list
or_range_list(Operand, [A, B]) ->
  or_function(conditional(equals, Operand, A),
              conditional(equals, Operand, B));

% Many items in a list
or_range_list(Operand, [A | B]) ->
  or_function(conditional(equals, Operand, A),
              or_range_list(Operand, B));

% When there's only one value
or_range_list(Operand, Value) ->
  conditional(equals, Operand, Value).

% Append to build up a list of ranges or values
append(A, B) when is_list(A) and is_list(B) ->
  A ++ B;

append(A, B) when is_list(A) and not is_list(B)->
  A ++ [B];

append(A, B) when not is_list(A) and is_list(B) ->
  [A] ++ B;

append(A, B) when not is_list(A) and not is_list(B) ->
  [A, B].

% Return a token value
unwrap({_,_,V}) -> V.

% Elixir Kernel Context
kernel_context() ->
  [{context, 'Elixir'}, {import, 'Elixir.Kernel'}].

% Atomize a token value
atomize(Token) ->
  list_to_atom(unwrap(Token)).


-file("/Users/kip/.local/share/mise/installs/erlang/28.3.1/lib/parsetools-2.7/include/yeccpre.hrl", 0).
%%
%% %CopyrightBegin%
%%
%% SPDX-License-Identifier: Apache-2.0
%%
%% Copyright Ericsson AB 1996-2025. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%
%% %CopyrightEnd%
%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% The parser generator will insert appropriate declarations before this line.%

-type yecc_ret() :: {'error', _} | {'ok', _}.

-ifdef (YECC_PARSE_DOC).
-doc ?YECC_PARSE_DOC.
-endif.
-spec parse(Tokens :: list()) -> yecc_ret().
parse(Tokens) ->
    yeccpars0(Tokens, {no_func, no_location}, 0, [], []).

-ifdef (YECC_PARSE_AND_SCAN_DOC).
-doc ?YECC_PARSE_AND_SCAN_DOC.
-endif.
-spec parse_and_scan({function() | {atom(), atom()}, [_]}
                     | {atom(), atom(), [_]}) -> yecc_ret().
parse_and_scan({F, A}) ->
    yeccpars0([], {{F, A}, no_location}, 0, [], []);
parse_and_scan({M, F, A}) ->
    Arity = length(A),
    yeccpars0([], {{fun M:F/Arity, A}, no_location}, 0, [], []).

-ifdef (YECC_FORMAT_ERROR_DOC).
-doc ?YECC_FORMAT_ERROR_DOC.
-endif.
-spec format_error(any()) -> [char() | list()].
format_error(Message) ->
    case io_lib:deep_char_list(Message) of
        true ->
            Message;
        _ ->
            io_lib:write(Message)
    end.

%% To be used in grammar files to throw an error message to the parser
%% toplevel. Doesn't have to be exported!
-compile({nowarn_unused_function, return_error/2}).
-spec return_error(erl_anno:location(), any()) -> no_return().
return_error(Location, Message) ->
    throw({error, {Location, ?MODULE, Message}}).

-define(CODE_VERSION, "1.4").

yeccpars0(Tokens, Tzr, State, States, Vstack) ->
    try yeccpars1(Tokens, Tzr, State, States, Vstack)
    catch 
        error: Error: Stacktrace ->
            try yecc_error_type(Error, Stacktrace) of
                Desc ->
                    erlang:raise(error, {yecc_bug, ?CODE_VERSION, Desc},
                                 Stacktrace)
            catch _:_ -> erlang:raise(error, Error, Stacktrace)
            end;
        %% Probably thrown from return_error/2:
        throw: {error, {_Location, ?MODULE, _M}} = Error ->
            Error
    end.

yecc_error_type(function_clause, [{?MODULE,F,ArityOrArgs,_} | _]) ->
    case atom_to_list(F) of
        "yeccgoto_" ++ SymbolL ->
            {ok,[{atom,_,Symbol}],_} = erl_scan:string(SymbolL),
            State = case ArityOrArgs of
                        [S,_,_,_,_,_,_] -> S;
                        _ -> state_is_unknown
                    end,
            {Symbol, State, missing_in_goto_table}
    end.

yeccpars1([Token | Tokens], Tzr, State, States, Vstack) ->
    yeccpars2(State, element(1, Token), States, Vstack, Token, Tokens, Tzr);
yeccpars1([], {{F, A},_Location}, State, States, Vstack) ->
    case apply(F, A) of
        {ok, Tokens, EndLocation} ->
            yeccpars1(Tokens, {{F, A}, EndLocation}, State, States, Vstack);
        {eof, EndLocation} ->
            yeccpars1([], {no_func, EndLocation}, State, States, Vstack);
        {error, Descriptor, _EndLocation} ->
            {error, Descriptor}
    end;
yeccpars1([], {no_func, no_location}, State, States, Vstack) ->
    Line = 999999,
    yeccpars2(State, '$end', States, Vstack, yecc_end(Line), [],
              {no_func, Line});
yeccpars1([], {no_func, EndLocation}, State, States, Vstack) ->
    yeccpars2(State, '$end', States, Vstack, yecc_end(EndLocation), [],
              {no_func, EndLocation}).

%% yeccpars1/7 is called from generated code.
%%
%% When using the {includefile, Includefile} option, make sure that
%% yeccpars1/7 can be found by parsing the file without following
%% include directives. yecc will otherwise assume that an old
%% yeccpre.hrl is included (one which defines yeccpars1/5).
yeccpars1(State1, State, States, Vstack, Token0, [Token | Tokens], Tzr) ->
    yeccpars2(State, element(1, Token), [State1 | States],
              [Token0 | Vstack], Token, Tokens, Tzr);
yeccpars1(State1, State, States, Vstack, Token0, [], {{_F,_A}, _Location}=Tzr) ->
    yeccpars1([], Tzr, State, [State1 | States], [Token0 | Vstack]);
yeccpars1(State1, State, States, Vstack, Token0, [], {no_func, no_location}) ->
    Location = yecctoken_end_location(Token0),
    yeccpars2(State, '$end', [State1 | States], [Token0 | Vstack],
              yecc_end(Location), [], {no_func, Location});
yeccpars1(State1, State, States, Vstack, Token0, [], {no_func, Location}) ->
    yeccpars2(State, '$end', [State1 | States], [Token0 | Vstack],
              yecc_end(Location), [], {no_func, Location}).

%% For internal use only.
yecc_end(Location) ->
    {'$end', Location}.

yecctoken_end_location(Token) ->
    try erl_anno:end_location(element(2, Token)) of
        undefined -> yecctoken_location(Token);
        Loc -> Loc
    catch _:_ -> yecctoken_location(Token)
    end.

-compile({nowarn_unused_function, yeccerror/1}).
yeccerror(Token) ->
    Text = yecctoken_to_string(Token),
    Location = yecctoken_location(Token),
    {error, {Location, ?MODULE, ["syntax error before: ", Text]}}.

-compile({nowarn_unused_function, yecctoken_to_string/1}).
yecctoken_to_string(Token) ->
    try erl_scan:text(Token) of
        undefined -> yecctoken2string(Token);
        Txt -> Txt
    catch _:_ -> yecctoken2string(Token)
    end.

yecctoken_location(Token) ->
    try erl_scan:location(Token)
    catch _:_ -> element(2, Token)
    end.

-compile({nowarn_unused_function, yecctoken2string/1}).
yecctoken2string(Token) ->
    try
        yecctoken2string1(Token)
    catch
        _:_ ->
            io_lib:format("~tp", [Token])
    end.

-compile({nowarn_unused_function, yecctoken2string1/1}).
yecctoken2string1({atom, _, A}) -> io_lib:write_atom(A);
yecctoken2string1({integer,_,N}) -> io_lib:write(N);
yecctoken2string1({float,_,F}) -> io_lib:write(F);
yecctoken2string1({char,_,C}) -> io_lib:write_char(C);
yecctoken2string1({var,_,V}) -> io_lib:format("~s", [V]);
yecctoken2string1({string,_,S}) -> io_lib:write_string(S);
yecctoken2string1({reserved_symbol, _, A}) -> io_lib:write(A);
yecctoken2string1({_Cat, _, Val}) -> io_lib:format("~tp", [Val]);
yecctoken2string1({dot, _}) -> "'.'";
yecctoken2string1({'$end', _}) -> [];
yecctoken2string1({Other, _}) when is_atom(Other) ->
    io_lib:write_atom(Other);
yecctoken2string1(Other) ->
    io_lib:format("~tp", [Other]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%



-file("src/plural_rules_parser.erl", 285).

-dialyzer({nowarn_function, yeccpars2/7}).
-compile({nowarn_unused_function,  yeccpars2/7}).
yeccpars2(0=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_0(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(1=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_1(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(2=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_2(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(3=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_3(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(4=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_4(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(5=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_5(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(6=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_6(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(7=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_7(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(8=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_8(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(9=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_9(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(10=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_10(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(11=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_11(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(12=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_12(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(13=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_13(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(14=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_14(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(15=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_15(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(16=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_16(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(17=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_17(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(18=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_18(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(19=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_11(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(20=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_20(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(21=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_21(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(22=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_22(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(23=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_21(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(24=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_24(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(25=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_25(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(26=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_26(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(27=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_27(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(28=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_21(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(29=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_29(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(30=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_30(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(31=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_31(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(32=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_21(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(33=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_33(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(34=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_21(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(35=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_35(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(36=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_36(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(37=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_37(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(38=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_38(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(39=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_21(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(40=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_40(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(41=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_21(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(42=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_42(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(43=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_21(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(44=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_21(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(45=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_45(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(46=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_46(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(47=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_47(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(48=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_48(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(49=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_21(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(50=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_50(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(51=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_51(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(52=S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_25(S, Cat, Ss, Stack, T, Ts, Tzr);
%% yeccpars2(53=S, Cat, Ss, Stack, T, Ts, Tzr) ->
%%  yeccpars2_53(S, Cat, Ss, Stack, T, Ts, Tzr);
yeccpars2(Other, _, _, _, _, _, _) ->
 erlang:error({yecc_bug,"1.4",{missing_state_in_action_table, Other}}).

-dialyzer({nowarn_function, yeccpars2_0/7}).
-compile({nowarn_unused_function,  yeccpars2_0/7}).
yeccpars2_0(S, 'operand', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 10, Ss, Stack, T, Ts, Tzr);
yeccpars2_0(S, 'sample', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 11, Ss, Stack, T, Ts, Tzr);
yeccpars2_0(_, _, _, _, T, _, _) ->
 yeccerror(T).

-dialyzer({nowarn_function, yeccpars2_1/7}).
-compile({nowarn_unused_function,  yeccpars2_1/7}).
yeccpars2_1(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 NewStack = yeccpars2_1_(Stack),
 yeccgoto_relation(hd(Ss), Cat, Ss, NewStack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccpars2_2/7}).
-compile({nowarn_unused_function,  yeccpars2_2/7}).
yeccpars2_2(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 NewStack = yeccpars2_2_(Stack),
 yeccgoto_plural_rule(hd(Ss), Cat, Ss, NewStack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccpars2_3/7}).
-compile({nowarn_unused_function,  yeccpars2_3/7}).
yeccpars2_3(S, 'and_predicate', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 52, Ss, Stack, T, Ts, Tzr);
yeccpars2_3(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 NewStack = yeccpars2_3_(Stack),
 yeccgoto_and_condition(hd(Ss), Cat, Ss, NewStack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccpars2_4/7}).
-compile({nowarn_unused_function,  yeccpars2_4/7}).
yeccpars2_4(_S, '$end', _Ss, Stack, _T, _Ts, _Tzr) ->
 {ok, hd(Stack)};
yeccpars2_4(_, _, _, _, T, _, _) ->
 yeccerror(T).

-dialyzer({nowarn_function, yeccpars2_5/7}).
-compile({nowarn_unused_function,  yeccpars2_5/7}).
yeccpars2_5(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 NewStack = yeccpars2_5_(Stack),
 yeccgoto_relation(hd(Ss), Cat, Ss, NewStack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccpars2_6/7}).
-compile({nowarn_unused_function,  yeccpars2_6/7}).
yeccpars2_6(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 NewStack = yeccpars2_6_(Stack),
 yeccgoto_relation(hd(Ss), Cat, Ss, NewStack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccpars2_7/7}).
-compile({nowarn_unused_function,  yeccpars2_7/7}).
yeccpars2_7(S, 'equals', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 29, Ss, Stack, T, Ts, Tzr);
yeccpars2_7(S, 'in', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 30, Ss, Stack, T, Ts, Tzr);
yeccpars2_7(S, 'is_op', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 31, Ss, Stack, T, Ts, Tzr);
yeccpars2_7(S, 'not_equals', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 32, Ss, Stack, T, Ts, Tzr);
yeccpars2_7(S, 'not_op', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 33, Ss, Stack, T, Ts, Tzr);
yeccpars2_7(S, 'within_op', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 34, Ss, Stack, T, Ts, Tzr);
yeccpars2_7(_, _, _, _, T, _, _) ->
 yeccerror(T).

-dialyzer({nowarn_function, yeccpars2_8/7}).
-compile({nowarn_unused_function,  yeccpars2_8/7}).
yeccpars2_8(S, 'sample', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 11, Ss, Stack, T, Ts, Tzr);
yeccpars2_8(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 NewStack = yeccpars2_8_(Stack),
 yeccgoto_plural_rule(hd(Ss), Cat, Ss, NewStack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccpars2_9/7}).
-compile({nowarn_unused_function,  yeccpars2_9/7}).
yeccpars2_9(S, 'or_predicate', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 25, Ss, Stack, T, Ts, Tzr);
yeccpars2_9(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 NewStack = yeccpars2_9_(Stack),
 yeccgoto_condition(hd(Ss), Cat, Ss, NewStack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccpars2_10/7}).
-compile({nowarn_unused_function,  yeccpars2_10/7}).
yeccpars2_10(S, 'mod', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 23, Ss, Stack, T, Ts, Tzr);
yeccpars2_10(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 NewStack = yeccpars2_10_(Stack),
 yeccgoto_expression(hd(Ss), Cat, Ss, NewStack, T, Ts, Tzr).

yeccpars2_11(S, 'ellipsis', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 16, Ss, Stack, T, Ts, Tzr);
yeccpars2_11(S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_21(S, Cat, Ss, Stack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccpars2_12/7}).
-compile({nowarn_unused_function,  yeccpars2_12/7}).
yeccpars2_12(S, 'tilde', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 21, Ss, Stack, T, Ts, Tzr);
yeccpars2_12(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 NewStack = yeccpars2_12_(Stack),
 yeccgoto_sample_range(hd(Ss), Cat, Ss, NewStack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccpars2_13/7}).
-compile({nowarn_unused_function,  yeccpars2_13/7}).
yeccpars2_13(S, 'comma', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 19, Ss, Stack, T, Ts, Tzr);
yeccpars2_13(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 NewStack = yeccpars2_13_(Stack),
 yeccgoto_sample_list(hd(Ss), Cat, Ss, NewStack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccpars2_14/7}).
-compile({nowarn_unused_function,  yeccpars2_14/7}).
yeccpars2_14(S, 'sample', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 11, Ss, Stack, T, Ts, Tzr);
yeccpars2_14(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 [_|Nss] = Ss,
 NewStack = yeccpars2_14_(Stack),
 yeccgoto_samples(hd(Nss), Cat, Nss, NewStack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccpars2_15/7}).
-compile({nowarn_unused_function,  yeccpars2_15/7}).
yeccpars2_15(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 NewStack = yeccpars2_15_(Stack),
 yeccgoto_value(hd(Ss), Cat, Ss, NewStack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccpars2_16/7}).
-compile({nowarn_unused_function,  yeccpars2_16/7}).
yeccpars2_16(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 NewStack = yeccpars2_16_(Stack),
 yeccgoto_sample_range(hd(Ss), Cat, Ss, NewStack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccpars2_17/7}).
-compile({nowarn_unused_function,  yeccpars2_17/7}).
yeccpars2_17(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 NewStack = yeccpars2_17_(Stack),
 yeccgoto_value(hd(Ss), Cat, Ss, NewStack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccpars2_18/7}).
-compile({nowarn_unused_function,  yeccpars2_18/7}).
yeccpars2_18(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 [_,_|Nss] = Ss,
 NewStack = yeccpars2_18_(Stack),
 yeccgoto_samples(hd(Nss), Cat, Nss, NewStack, T, Ts, Tzr).

%% yeccpars2_19: see yeccpars2_11

-dialyzer({nowarn_function, yeccpars2_20/7}).
-compile({nowarn_unused_function,  yeccpars2_20/7}).
yeccpars2_20(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 [_,_|Nss] = Ss,
 NewStack = yeccpars2_20_(Stack),
 yeccgoto_sample_list(hd(Nss), Cat, Nss, NewStack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccpars2_21/7}).
-compile({nowarn_unused_function,  yeccpars2_21/7}).
yeccpars2_21(S, 'decimal', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 15, Ss, Stack, T, Ts, Tzr);
yeccpars2_21(S, 'integer', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 17, Ss, Stack, T, Ts, Tzr);
yeccpars2_21(_, _, _, _, T, _, _) ->
 yeccerror(T).

-dialyzer({nowarn_function, yeccpars2_22/7}).
-compile({nowarn_unused_function,  yeccpars2_22/7}).
yeccpars2_22(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 [_,_|Nss] = Ss,
 NewStack = yeccpars2_22_(Stack),
 yeccgoto_sample_range(hd(Nss), Cat, Nss, NewStack, T, Ts, Tzr).

%% yeccpars2_23: see yeccpars2_21

-dialyzer({nowarn_function, yeccpars2_24/7}).
-compile({nowarn_unused_function,  yeccpars2_24/7}).
yeccpars2_24(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 [_,_|Nss] = Ss,
 NewStack = yeccpars2_24_(Stack),
 yeccgoto_expression(hd(Nss), Cat, Nss, NewStack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccpars2_25/7}).
-compile({nowarn_unused_function,  yeccpars2_25/7}).
yeccpars2_25(S, 'operand', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 10, Ss, Stack, T, Ts, Tzr);
yeccpars2_25(_, _, _, _, T, _, _) ->
 yeccerror(T).

-dialyzer({nowarn_function, yeccpars2_26/7}).
-compile({nowarn_unused_function,  yeccpars2_26/7}).
yeccpars2_26(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 [_,_|Nss] = Ss,
 NewStack = yeccpars2_26_(Stack),
 yeccgoto_condition(hd(Nss), Cat, Nss, NewStack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccpars2_27/7}).
-compile({nowarn_unused_function,  yeccpars2_27/7}).
yeccpars2_27(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 [_|Nss] = Ss,
 NewStack = yeccpars2_27_(Stack),
 yeccgoto_plural_rule(hd(Nss), Cat, Nss, NewStack, T, Ts, Tzr).

%% yeccpars2_28: see yeccpars2_21

-dialyzer({nowarn_function, yeccpars2_29/7}).
-compile({nowarn_unused_function,  yeccpars2_29/7}).
yeccpars2_29(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 NewStack = yeccpars2_29_(Stack),
 yeccgoto_conditional(hd(Ss), Cat, Ss, NewStack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccpars2_30/7}).
-compile({nowarn_unused_function,  yeccpars2_30/7}).
yeccpars2_30(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 NewStack = yeccpars2_30_(Stack),
 yeccgoto_conditional(hd(Ss), Cat, Ss, NewStack, T, Ts, Tzr).

yeccpars2_31(S, 'not_op', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 49, Ss, Stack, T, Ts, Tzr);
yeccpars2_31(S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_21(S, Cat, Ss, Stack, T, Ts, Tzr).

%% yeccpars2_32: see yeccpars2_21

-dialyzer({nowarn_function, yeccpars2_33/7}).
-compile({nowarn_unused_function,  yeccpars2_33/7}).
yeccpars2_33(S, 'in', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 43, Ss, Stack, T, Ts, Tzr);
yeccpars2_33(S, 'within_op', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 44, Ss, Stack, T, Ts, Tzr);
yeccpars2_33(_, _, _, _, T, _, _) ->
 yeccerror(T).

%% yeccpars2_34: see yeccpars2_21

-dialyzer({nowarn_function, yeccpars2_35/7}).
-compile({nowarn_unused_function,  yeccpars2_35/7}).
yeccpars2_35(S, 'range_op', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 41, Ss, Stack, T, Ts, Tzr);
yeccpars2_35(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 NewStack = yeccpars2_35_(Stack),
 yeccgoto_range_or_value(hd(Ss), Cat, Ss, NewStack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccpars2_36/7}).
-compile({nowarn_unused_function,  yeccpars2_36/7}).
yeccpars2_36(S, 'comma', Ss, Stack, T, Ts, Tzr) ->
 yeccpars1(S, 39, Ss, Stack, T, Ts, Tzr);
yeccpars2_36(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 NewStack = yeccpars2_36_(Stack),
 yeccgoto_range_list(hd(Ss), Cat, Ss, NewStack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccpars2_37/7}).
-compile({nowarn_unused_function,  yeccpars2_37/7}).
yeccpars2_37(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 [_,_|Nss] = Ss,
 NewStack = yeccpars2_37_(Stack),
 yeccgoto_within_relation(hd(Nss), Cat, Nss, NewStack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccpars2_38/7}).
-compile({nowarn_unused_function,  yeccpars2_38/7}).
yeccpars2_38(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 NewStack = yeccpars2_38_(Stack),
 yeccgoto_range_or_value(hd(Ss), Cat, Ss, NewStack, T, Ts, Tzr).

%% yeccpars2_39: see yeccpars2_21

-dialyzer({nowarn_function, yeccpars2_40/7}).
-compile({nowarn_unused_function,  yeccpars2_40/7}).
yeccpars2_40(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 [_,_|Nss] = Ss,
 NewStack = yeccpars2_40_(Stack),
 yeccgoto_range_list(hd(Nss), Cat, Nss, NewStack, T, Ts, Tzr).

%% yeccpars2_41: see yeccpars2_21

-dialyzer({nowarn_function, yeccpars2_42/7}).
-compile({nowarn_unused_function,  yeccpars2_42/7}).
yeccpars2_42(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 [_,_|Nss] = Ss,
 NewStack = yeccpars2_42_(Stack),
 yeccgoto_range(hd(Nss), Cat, Nss, NewStack, T, Ts, Tzr).

%% yeccpars2_43: see yeccpars2_21

%% yeccpars2_44: see yeccpars2_21

-dialyzer({nowarn_function, yeccpars2_45/7}).
-compile({nowarn_unused_function,  yeccpars2_45/7}).
yeccpars2_45(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 [_,_,_|Nss] = Ss,
 NewStack = yeccpars2_45_(Stack),
 yeccgoto_within_relation(hd(Nss), Cat, Nss, NewStack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccpars2_46/7}).
-compile({nowarn_unused_function,  yeccpars2_46/7}).
yeccpars2_46(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 [_,_,_|Nss] = Ss,
 NewStack = yeccpars2_46_(Stack),
 yeccgoto_in_relation(hd(Nss), Cat, Nss, NewStack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccpars2_47/7}).
-compile({nowarn_unused_function,  yeccpars2_47/7}).
yeccpars2_47(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 [_,_|Nss] = Ss,
 NewStack = yeccpars2_47_(Stack),
 yeccgoto_in_relation(hd(Nss), Cat, Nss, NewStack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccpars2_48/7}).
-compile({nowarn_unused_function,  yeccpars2_48/7}).
yeccpars2_48(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 [_,_|Nss] = Ss,
 NewStack = yeccpars2_48_(Stack),
 yeccgoto_is_relation(hd(Nss), Cat, Nss, NewStack, T, Ts, Tzr).

%% yeccpars2_49: see yeccpars2_21

-dialyzer({nowarn_function, yeccpars2_50/7}).
-compile({nowarn_unused_function,  yeccpars2_50/7}).
yeccpars2_50(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 [_,_,_|Nss] = Ss,
 NewStack = yeccpars2_50_(Stack),
 yeccgoto_is_relation(hd(Nss), Cat, Nss, NewStack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccpars2_51/7}).
-compile({nowarn_unused_function,  yeccpars2_51/7}).
yeccpars2_51(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 [_,_|Nss] = Ss,
 NewStack = yeccpars2_51_(Stack),
 yeccgoto_in_relation(hd(Nss), Cat, Nss, NewStack, T, Ts, Tzr).

%% yeccpars2_52: see yeccpars2_25

-dialyzer({nowarn_function, yeccpars2_53/7}).
-compile({nowarn_unused_function,  yeccpars2_53/7}).
yeccpars2_53(_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 [_,_|Nss] = Ss,
 NewStack = yeccpars2_53_(Stack),
 yeccgoto_and_condition(hd(Nss), Cat, Nss, NewStack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccgoto_and_condition/7}).
-compile({nowarn_unused_function,  yeccgoto_and_condition/7}).
yeccgoto_and_condition(0, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_9(9, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_and_condition(25, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_9(9, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_and_condition(52=_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_53(_S, Cat, Ss, Stack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccgoto_condition/7}).
-compile({nowarn_unused_function,  yeccgoto_condition/7}).
yeccgoto_condition(0, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_8(8, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_condition(25=_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_26(_S, Cat, Ss, Stack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccgoto_conditional/7}).
-compile({nowarn_unused_function,  yeccgoto_conditional/7}).
yeccgoto_conditional(7, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_21(28, Cat, Ss, Stack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccgoto_expression/7}).
-compile({nowarn_unused_function,  yeccgoto_expression/7}).
yeccgoto_expression(0, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_7(7, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_expression(25, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_7(7, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_expression(52, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_7(7, Cat, Ss, Stack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccgoto_in_relation/7}).
-compile({nowarn_unused_function,  yeccgoto_in_relation/7}).
yeccgoto_in_relation(0=_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_6(_S, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_in_relation(25=_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_6(_S, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_in_relation(52=_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_6(_S, Cat, Ss, Stack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccgoto_is_relation/7}).
-compile({nowarn_unused_function,  yeccgoto_is_relation/7}).
yeccgoto_is_relation(0=_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_5(_S, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_is_relation(25=_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_5(_S, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_is_relation(52=_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_5(_S, Cat, Ss, Stack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccgoto_plural_rule/7}).
-compile({nowarn_unused_function,  yeccgoto_plural_rule/7}).
yeccgoto_plural_rule(0, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_4(4, Cat, Ss, Stack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccgoto_range/7}).
-compile({nowarn_unused_function,  yeccgoto_range/7}).
yeccgoto_range(28=_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_38(_S, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_range(32=_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_38(_S, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_range(34=_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_38(_S, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_range(39=_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_38(_S, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_range(43=_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_38(_S, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_range(44=_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_38(_S, Cat, Ss, Stack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccgoto_range_list/7}).
-compile({nowarn_unused_function,  yeccgoto_range_list/7}).
yeccgoto_range_list(28=_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_51(_S, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_range_list(32=_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_47(_S, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_range_list(34=_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_37(_S, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_range_list(39=_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_40(_S, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_range_list(43=_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_46(_S, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_range_list(44=_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_45(_S, Cat, Ss, Stack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccgoto_range_or_value/7}).
-compile({nowarn_unused_function,  yeccgoto_range_or_value/7}).
yeccgoto_range_or_value(28, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_36(36, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_range_or_value(32, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_36(36, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_range_or_value(34, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_36(36, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_range_or_value(39, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_36(36, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_range_or_value(43, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_36(36, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_range_or_value(44, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_36(36, Cat, Ss, Stack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccgoto_relation/7}).
-compile({nowarn_unused_function,  yeccgoto_relation/7}).
yeccgoto_relation(0, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_3(3, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_relation(25, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_3(3, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_relation(52, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_3(3, Cat, Ss, Stack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccgoto_sample_list/7}).
-compile({nowarn_unused_function,  yeccgoto_sample_list/7}).
yeccgoto_sample_list(11, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_14(14, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_sample_list(19=_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_20(_S, Cat, Ss, Stack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccgoto_sample_range/7}).
-compile({nowarn_unused_function,  yeccgoto_sample_range/7}).
yeccgoto_sample_range(11, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_13(13, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_sample_range(19, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_13(13, Cat, Ss, Stack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccgoto_samples/7}).
-compile({nowarn_unused_function,  yeccgoto_samples/7}).
yeccgoto_samples(0=_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_2(_S, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_samples(8=_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_27(_S, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_samples(14=_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_18(_S, Cat, Ss, Stack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccgoto_value/7}).
-compile({nowarn_unused_function,  yeccgoto_value/7}).
yeccgoto_value(11, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_12(12, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_value(19, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_12(12, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_value(21=_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_22(_S, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_value(23=_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_24(_S, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_value(28, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_35(35, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_value(31=_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_48(_S, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_value(32, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_35(35, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_value(34, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_35(35, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_value(39, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_35(35, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_value(41=_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_42(_S, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_value(43, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_35(35, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_value(44, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_35(35, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_value(49=_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_50(_S, Cat, Ss, Stack, T, Ts, Tzr).

-dialyzer({nowarn_function, yeccgoto_within_relation/7}).
-compile({nowarn_unused_function,  yeccgoto_within_relation/7}).
yeccgoto_within_relation(0=_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_1(_S, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_within_relation(25=_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_1(_S, Cat, Ss, Stack, T, Ts, Tzr);
yeccgoto_within_relation(52=_S, Cat, Ss, Stack, T, Ts, Tzr) ->
 yeccpars2_1(_S, Cat, Ss, Stack, T, Ts, Tzr).

-compile({inline,yeccpars2_1_/1}).
-dialyzer({nowarn_function, yeccpars2_1_/1}).
-compile({nowarn_unused_function,  yeccpars2_1_/1}).
-file("src/plural_rules_parser.yrl", 44).
yeccpars2_1_(__Stack0) ->
 [___1 | __Stack] = __Stack0,
 [begin
                                        ___1
  end | __Stack].

-compile({inline,yeccpars2_2_/1}).
-dialyzer({nowarn_function, yeccpars2_2_/1}).
-compile({nowarn_unused_function,  yeccpars2_2_/1}).
-file("src/plural_rules_parser.yrl", 34).
yeccpars2_2_(__Stack0) ->
 [___1 | __Stack] = __Stack0,
 [begin
                                ___1
  end | __Stack].

-compile({inline,yeccpars2_3_/1}).
-dialyzer({nowarn_function, yeccpars2_3_/1}).
-compile({nowarn_unused_function,  yeccpars2_3_/1}).
-file("src/plural_rules_parser.yrl", 40).
yeccpars2_3_(__Stack0) ->
 [___1 | __Stack] = __Stack0,
 [begin
                                 ___1
  end | __Stack].

-compile({inline,yeccpars2_5_/1}).
-dialyzer({nowarn_function, yeccpars2_5_/1}).
-compile({nowarn_unused_function,  yeccpars2_5_/1}).
-file("src/plural_rules_parser.yrl", 42).
yeccpars2_5_(__Stack0) ->
 [___1 | __Stack] = __Stack0,
 [begin
                                    ___1
  end | __Stack].

-compile({inline,yeccpars2_6_/1}).
-dialyzer({nowarn_function, yeccpars2_6_/1}).
-compile({nowarn_unused_function,  yeccpars2_6_/1}).
-file("src/plural_rules_parser.yrl", 43).
yeccpars2_6_(__Stack0) ->
 [___1 | __Stack] = __Stack0,
 [begin
                                    ___1
  end | __Stack].

-compile({inline,yeccpars2_8_/1}).
-dialyzer({nowarn_function, yeccpars2_8_/1}).
-compile({nowarn_unused_function,  yeccpars2_8_/1}).
-file("src/plural_rules_parser.yrl", 33).
yeccpars2_8_(__Stack0) ->
 [___1 | __Stack] = __Stack0,
 [begin
                                  [{rule, ___1}]
  end | __Stack].

-compile({inline,yeccpars2_9_/1}).
-dialyzer({nowarn_function, yeccpars2_9_/1}).
-compile({nowarn_unused_function,  yeccpars2_9_/1}).
-file("src/plural_rules_parser.yrl", 37).
yeccpars2_9_(__Stack0) ->
 [___1 | __Stack] = __Stack0,
 [begin
                                      ___1
  end | __Stack].

-compile({inline,yeccpars2_10_/1}).
-dialyzer({nowarn_function, yeccpars2_10_/1}).
-compile({nowarn_unused_function,  yeccpars2_10_/1}).
-file("src/plural_rules_parser.yrl", 62).
yeccpars2_10_(__Stack0) ->
 [___1 | __Stack] = __Stack0,
 [begin
                                operand(___1)
  end | __Stack].

-compile({inline,yeccpars2_12_/1}).
-dialyzer({nowarn_function, yeccpars2_12_/1}).
-compile({nowarn_unused_function,  yeccpars2_12_/1}).
-file("src/plural_rules_parser.yrl", 82).
yeccpars2_12_(__Stack0) ->
 [___1 | __Stack] = __Stack0,
 [begin
                              ___1
  end | __Stack].

-compile({inline,yeccpars2_13_/1}).
-dialyzer({nowarn_function, yeccpars2_13_/1}).
-compile({nowarn_unused_function,  yeccpars2_13_/1}).
-file("src/plural_rules_parser.yrl", 79).
yeccpars2_13_(__Stack0) ->
 [___1 | __Stack] = __Stack0,
 [begin
                                     [___1]
  end | __Stack].

-compile({inline,yeccpars2_14_/1}).
-dialyzer({nowarn_function, yeccpars2_14_/1}).
-compile({nowarn_unused_function,  yeccpars2_14_/1}).
-file("src/plural_rules_parser.yrl", 76).
yeccpars2_14_(__Stack0) ->
 [___2,___1 | __Stack] = __Stack0,
 [begin
                                           [{unwrap(___1), ___2}]
  end | __Stack].

-compile({inline,yeccpars2_15_/1}).
-dialyzer({nowarn_function, yeccpars2_15_/1}).
-compile({nowarn_unused_function,  yeccpars2_15_/1}).
-file("src/plural_rules_parser.yrl", 73).
yeccpars2_15_(__Stack0) ->
 [___1 | __Stack] = __Stack0,
 [begin
                                unwrap(___1)
  end | __Stack].

-compile({inline,yeccpars2_16_/1}).
-dialyzer({nowarn_function, yeccpars2_16_/1}).
-compile({nowarn_unused_function,  yeccpars2_16_/1}).
-file("src/plural_rules_parser.yrl", 83).
yeccpars2_16_(__Stack0) ->
 [___1 | __Stack] = __Stack0,
 [begin
                                 'ellipsis'
  end | __Stack].

-compile({inline,yeccpars2_17_/1}).
-dialyzer({nowarn_function, yeccpars2_17_/1}).
-compile({nowarn_unused_function,  yeccpars2_17_/1}).
-file("src/plural_rules_parser.yrl", 72).
yeccpars2_17_(__Stack0) ->
 [___1 | __Stack] = __Stack0,
 [begin
                                unwrap(___1)
  end | __Stack].

-compile({inline,yeccpars2_18_/1}).
-dialyzer({nowarn_function, yeccpars2_18_/1}).
-compile({nowarn_unused_function,  yeccpars2_18_/1}).
-file("src/plural_rules_parser.yrl", 75).
yeccpars2_18_(__Stack0) ->
 [___3,___2,___1 | __Stack] = __Stack0,
 [begin
                                                   append({unwrap(___1), ___2}, ___3)
  end | __Stack].

-compile({inline,yeccpars2_20_/1}).
-dialyzer({nowarn_function, yeccpars2_20_/1}).
-compile({nowarn_unused_function,  yeccpars2_20_/1}).
-file("src/plural_rules_parser.yrl", 78).
yeccpars2_20_(__Stack0) ->
 [___3,___2,___1 | __Stack] = __Stack0,
 [begin
                                                       append(___1, ___3)
  end | __Stack].

-compile({inline,yeccpars2_22_/1}).
-dialyzer({nowarn_function, yeccpars2_22_/1}).
-compile({nowarn_unused_function,  yeccpars2_22_/1}).
-file("src/plural_rules_parser.yrl", 81).
yeccpars2_22_(__Stack0) ->
 [___3,___2,___1 | __Stack] = __Stack0,
 [begin
                                          range(___1, ___3)
  end | __Stack].

-compile({inline,yeccpars2_24_/1}).
-dialyzer({nowarn_function, yeccpars2_24_/1}).
-compile({nowarn_unused_function,  yeccpars2_24_/1}).
-file("src/plural_rules_parser.yrl", 61).
yeccpars2_24_(__Stack0) ->
 [___3,___2,___1 | __Stack] = __Stack0,
 [begin
                                          mod(___1, ___3)
  end | __Stack].

-compile({inline,yeccpars2_26_/1}).
-dialyzer({nowarn_function, yeccpars2_26_/1}).
-compile({nowarn_unused_function,  yeccpars2_26_/1}).
-file("src/plural_rules_parser.yrl", 36).
yeccpars2_26_(__Stack0) ->
 [___3,___2,___1 | __Stack] = __Stack0,
 [begin
                                                             or_function(___1, ___3)
  end | __Stack].

-compile({inline,yeccpars2_27_/1}).
-dialyzer({nowarn_function, yeccpars2_27_/1}).
-compile({nowarn_unused_function,  yeccpars2_27_/1}).
-file("src/plural_rules_parser.yrl", 32).
yeccpars2_27_(__Stack0) ->
 [___2,___1 | __Stack] = __Stack0,
 [begin
                                          append({rule, ___1}, ___2)
  end | __Stack].

-compile({inline,yeccpars2_29_/1}).
-dialyzer({nowarn_function, yeccpars2_29_/1}).
-compile({nowarn_unused_function,  yeccpars2_29_/1}).
-file("src/plural_rules_parser.yrl", 57).
yeccpars2_29_(__Stack0) ->
 [___1 | __Stack] = __Stack0,
 [begin
                               '='
  end | __Stack].

-compile({inline,yeccpars2_30_/1}).
-dialyzer({nowarn_function, yeccpars2_30_/1}).
-compile({nowarn_unused_function,  yeccpars2_30_/1}).
-file("src/plural_rules_parser.yrl", 56).
yeccpars2_30_(__Stack0) ->
 [___1 | __Stack] = __Stack0,
 [begin
                           'in'
  end | __Stack].

-compile({inline,yeccpars2_35_/1}).
-dialyzer({nowarn_function, yeccpars2_35_/1}).
-compile({nowarn_unused_function,  yeccpars2_35_/1}).
-file("src/plural_rules_parser.yrl", 68).
yeccpars2_35_(__Stack0) ->
 [___1 | __Stack] = __Stack0,
 [begin
                              ___1
  end | __Stack].

-compile({inline,yeccpars2_36_/1}).
-dialyzer({nowarn_function, yeccpars2_36_/1}).
-compile({nowarn_unused_function,  yeccpars2_36_/1}).
-file("src/plural_rules_parser.yrl", 65).
yeccpars2_36_(__Stack0) ->
 [___1 | __Stack] = __Stack0,
 [begin
                                       ___1
  end | __Stack].

-compile({inline,yeccpars2_37_/1}).
-dialyzer({nowarn_function, yeccpars2_37_/1}).
-compile({nowarn_unused_function,  yeccpars2_37_/1}).
-file("src/plural_rules_parser.yrl", 53).
yeccpars2_37_(__Stack0) ->
 [___3,___2,___1 | __Stack] = __Stack0,
 [begin
                                                        or_range_list(___1, ___3)
  end | __Stack].

-compile({inline,yeccpars2_38_/1}).
-dialyzer({nowarn_function, yeccpars2_38_/1}).
-compile({nowarn_unused_function,  yeccpars2_38_/1}).
-file("src/plural_rules_parser.yrl", 67).
yeccpars2_38_(__Stack0) ->
 [___1 | __Stack] = __Stack0,
 [begin
                              ___1
  end | __Stack].

-compile({inline,yeccpars2_40_/1}).
-dialyzer({nowarn_function, yeccpars2_40_/1}).
-compile({nowarn_unused_function,  yeccpars2_40_/1}).
-file("src/plural_rules_parser.yrl", 64).
yeccpars2_40_(__Stack0) ->
 [___3,___2,___1 | __Stack] = __Stack0,
 [begin
                                                        append(___1, ___3)
  end | __Stack].

-compile({inline,yeccpars2_42_/1}).
-dialyzer({nowarn_function, yeccpars2_42_/1}).
-compile({nowarn_unused_function,  yeccpars2_42_/1}).
-file("src/plural_rules_parser.yrl", 70).
yeccpars2_42_(__Stack0) ->
 [___3,___2,___1 | __Stack] = __Stack0,
 [begin
                                             range(___1, ___3)
  end | __Stack].

-compile({inline,yeccpars2_45_/1}).
-dialyzer({nowarn_function, yeccpars2_45_/1}).
-compile({nowarn_unused_function,  yeccpars2_45_/1}).
-file("src/plural_rules_parser.yrl", 54).
yeccpars2_45_(__Stack0) ->
 [___4,___3,___2,___1 | __Stack] = __Stack0,
 [begin
                                                               not_function(or_range_list(___1, ___4))
  end | __Stack].

-compile({inline,yeccpars2_46_/1}).
-dialyzer({nowarn_function, yeccpars2_46_/1}).
-compile({nowarn_unused_function,  yeccpars2_46_/1}).
-file("src/plural_rules_parser.yrl", 51).
yeccpars2_46_(__Stack0) ->
 [___4,___3,___2,___1 | __Stack] = __Stack0,
 [begin
                                                        not_function(or_range_list(___1, ___4))
  end | __Stack].

-compile({inline,yeccpars2_47_/1}).
-dialyzer({nowarn_function, yeccpars2_47_/1}).
-compile({nowarn_unused_function,  yeccpars2_47_/1}).
-file("src/plural_rules_parser.yrl", 49).
yeccpars2_47_(__Stack0) ->
 [___3,___2,___1 | __Stack] = __Stack0,
 [begin
                                                         not_function(or_range_list(___1, ___3))
  end | __Stack].

-compile({inline,yeccpars2_48_/1}).
-dialyzer({nowarn_function, yeccpars2_48_/1}).
-compile({nowarn_unused_function,  yeccpars2_48_/1}).
-file("src/plural_rules_parser.yrl", 46).
yeccpars2_48_(__Stack0) ->
 [___3,___2,___1 | __Stack] = __Stack0,
 [begin
                                               or_range_list(___1, ___3)
  end | __Stack].

-compile({inline,yeccpars2_50_/1}).
-dialyzer({nowarn_function, yeccpars2_50_/1}).
-compile({nowarn_unused_function,  yeccpars2_50_/1}).
-file("src/plural_rules_parser.yrl", 47).
yeccpars2_50_(__Stack0) ->
 [___4,___3,___2,___1 | __Stack] = __Stack0,
 [begin
                                                      not_function(or_range_list(___1, ___4))
  end | __Stack].

-compile({inline,yeccpars2_51_/1}).
-dialyzer({nowarn_function, yeccpars2_51_/1}).
-compile({nowarn_unused_function,  yeccpars2_51_/1}).
-file("src/plural_rules_parser.yrl", 50).
yeccpars2_51_(__Stack0) ->
 [___3,___2,___1 | __Stack] = __Stack0,
 [begin
                                                          or_range_list(___1, ___3)
  end | __Stack].

-compile({inline,yeccpars2_53_/1}).
-dialyzer({nowarn_function, yeccpars2_53_/1}).
-compile({nowarn_unused_function,  yeccpars2_53_/1}).
-file("src/plural_rules_parser.yrl", 39).
yeccpars2_53_(__Stack0) ->
 [___3,___2,___1 | __Stack] = __Stack0,
 [begin
                                                             and_function(___1, ___3)
  end | __Stack].


-file("src/plural_rules_parser.yrl", 178).
