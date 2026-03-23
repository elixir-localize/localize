# Plan: Replace deprecated `{:error, {module, reason}}` patterns

## Background

The ex_cldr convention was `{:error, {ExceptionModule, "message"}}`. Localize uses `{:error, ExceptionModule.exception(bindings)}` instead, returning proper exception structs. A few remnants of the old pattern remain.

## Items to fix

### 1. `lib/localize/message/message.ex:51` — Outdated doc string

The `format/3` doc says:

```
* `{:error, {module, reason}}` on failure.
```

The spec (already corrected) is `{:error, Exception.t()}` and the implementation returns `{:error, %BindError{}}` or `{:error, %FormatError{}}`. Update the doc to match:

```
* `{:error, exception}` where `exception` is a `t:Localize.BindError.t/0`
  for unbound variables or a `t:Localize.FormatError.t/0` for formatting
  failures.
```

### 2. `lib/localize/language_tag.ex:207` — Wrong spec for `parse/1`

The spec is:

```elixir
@spec parse(String.t()) :: {:ok, t()} | {:error, module()}
```

`Parser.parse/1` actually returns `{:error, struct()}` (an exception struct from the RFC 5646 parser). Fix to:

```elixir
@spec parse(String.t()) :: {:ok, t()} | {:error, Exception.t()}
```

### 3. `lib/localize/language_tag.ex:299` — Backward-compat clause in `new!/1`

The function has three error clauses:

```elixir
{:error, %{__exception__: true} = exception} -> raise exception
{:error, {exception, reason}} when is_atom(exception) -> raise exception, reason
{:error, reason} -> raise ArgumentError, "#{inspect(reason)}"
```

The middle clause handles the old ex_cldr format. Since `new/1` calls `parse/1` then `canonicalize/1` then `validate_locale/1`, all of which now return exception structs, this clause is dead code. Simplify to:

```elixir
{:error, exception} -> raise exception
```

### Items that are NOT deprecated-pattern issues

The `{:error, {_line, _parser, [message, context]}}` patterns in `lib/localize/number/format/compiler.ex` (lines 128, 154) and `lib/localize/datetime/format/compiler.ex` (line 70) are **internal Erlang yecc/leex parser error tuples**, not the ex_cldr convention. These are correct and should not be changed.
