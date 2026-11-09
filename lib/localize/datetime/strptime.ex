defmodule Localize.DateTime.Strptime do
  @moduledoc """
  Translates a `Calendar.strftime/3` format into the CLDR pattern that
  `Localize.Date.parse/2`, `Localize.Time.parse/2` and
  `Localize.DateTime.parse/2` read with, so text written with a strftime
  format, by `Calendar.strftime/3`, by C's `strftime(3)` or by Python or
  Ruby, is read back by the same parsers in any locale.

  `Localize.Date.strptime/3`, `Localize.Time.strptime/3` and
  `Localize.DateTime.strptime/3` call `pattern/2` and then `parse/2`.
  This module is the translation alone. The [strptime
  guide](strptime.html) lists every directive, what each reads and
  where the reading differs from C's `strptime(3)`.

  """

  # A directive and the pattern field that reads what it writes. The
  # parsers read a field whatever its width, so `%d` and `%e`, or `%H`
  # and `%k`, translate to fields that differ only in the padding the
  # formatter would write.
  @directives %{
    ?a => "EEE",
    ?A => "EEEE",
    ?b => "MMM",
    ?h => "MMM",
    ?B => "MMMM",
    ?d => "dd",
    ?e => "d",
    ?f => "SSSSSS",
    ?H => "HH",
    ?k => "H",
    ?I => "hh",
    ?l => "h",
    ?j => "DDD",
    ?m => "MM",
    ?M => "mm",
    ?p => "a",
    ?P => "a",
    ?q => "Q",
    ?S => "ss",
    ?y => "yy",
    ?Y => "y",
    ?z => "xx",
    ?Z => "zzzz",
    ?D => "MM/dd/yy",
    ?F => "y-MM-dd",
    ?T => "HH:mm:ss",
    ?R => "HH:mm"
  }

  # The directives that stand for a format of their own, the option that
  # holds it, and the format `Calendar.strftime/3` uses when the option
  # is not given.
  @preferred %{
    ?c => {:preferred_datetime, "%Y-%m-%d %H:%M:%S"},
    ?x => {:preferred_date, "%Y-%m-%d"},
    ?X => {:preferred_time, "%H:%M:%S"}
  }

  @preferred_options Enum.map(Map.values(@preferred), &elem(&1, 0))

  # A newline or a tab in the format is read as a space, which the
  # parsers match to a run of spaces in the text.
  @whitespace_directives [?n, ?t]

  # `%-d`, `%_d`, `%05d`: padding and width that a formatter honours and
  # a parser has no use for.
  @padding [?-, ?_, ?0]

  @doc """
  Translates a `Calendar.strftime/3` format into a CLDR date and time
  pattern.

  Each directive becomes the pattern field that reads what the directive
  writes; any other letter in the format is quoted, so it is read as the
  literal text it is; `%%` is a literal percent sign; and padding and
  width modifiers (`%-d`, `%_H`, `%05Y`) are accepted and ignored, since
  the parsers read a field at any width.

  ### Arguments

  * `format` is a `Calendar.strftime/3` format string.

  * `options` is a keyword list of options.

  ### Options

  * `:preferred_datetime`, `:preferred_date` and `:preferred_time` are
    the strftime formats `%c`, `%x` and `%X` stand for, as
    `Calendar.strftime/3` takes them. The defaults are
    `"%Y-%m-%d %H:%M:%S"`, `"%Y-%m-%d"` and `"%H:%M:%S"`. A preferred
    format may not itself contain `%c`, `%x` or `%X`.

  ### Returns

  * `{:ok, pattern}` with the CLDR pattern, or

  * `{:error, exception}`, a `t:Localize.DateTimeFormatError.t/0` with
    the reason `:unsupported_directive` and the directive in `:detail`
    for a directive Localize does not read (`%s`, `%u`, `%w`, `%U`,
    `%W`, `%V`, `%G`, `%C`, the `%E` and `%O` modifiers, or a `%` that
    ends the format), or a `t:Localize.InvalidValueError.t/0` if
    `format` is not a string or an option is malformed.

  ### Examples

      iex> Localize.DateTime.Strptime.pattern("%Y-%m-%dT%H:%M:%S")
      {:ok, "y-MM-dd'T'HH:mm:ss"}

      iex> Localize.DateTime.Strptime.pattern("%d %B %Y at %I:%M %p")
      {:ok, "dd MMMM y 'at' hh:mm a"}

      iex> Localize.DateTime.Strptime.pattern("%c")
      {:ok, "y-MM-dd HH:mm:ss"}

      iex> Localize.DateTime.Strptime.pattern("%x %X", preferred_date: "%d/%m/%Y")
      {:ok, "dd/MM/y HH:mm:ss"}

      iex> Localize.DateTime.Strptime.pattern("%Y week %V")
      {:error,
       %Localize.DateTimeFormatError{format: "%Y week %V", reason: :unsupported_directive, detail: "%V"}}

  """
  @spec pattern(String.t(), Keyword.t()) :: {:ok, String.t()} | {:error, Exception.t()}
  def pattern(format, options \\ [])

  def pattern(format, options) when is_binary(format) and is_list(options) do
    with :ok <- validate_format(format),
         :ok <- validate_options(options) do
      translate(format, format, options, false)
    end
  end

  def pattern(format, options) when is_binary(format) do
    {:error, Localize.Utils.Helpers.invalid_options(options)}
  end

  def pattern(format, _options) do
    {:error, Localize.Utils.Helpers.invalid_value(format, "a strftime format string")}
  end

  @doc """
  The options `parse/2` takes from the options given to a `strptime/3`
  function: the options less `:preferred_datetime`, `:preferred_date`
  and `:preferred_time`, with `:format` set to the translated pattern.

  ### Arguments

  * `options` is the keyword list given to `strptime/3`.

  * `pattern` is the CLDR pattern `pattern/2` returned.

  ### Returns

  * `{:ok, options}` with the keyword list of options for `parse/2`, or

  * `{:error, exception}`, a `t:Localize.InvalidValueError.t/0` if
    `options` is not a keyword list or `pattern` is not a string.

  ### Examples

      iex> Localize.DateTime.Strptime.parse_options([locale: :de, preferred_date: "%d.%m.%Y"], "dd.MM.y")
      {:ok, [format: "dd.MM.y", locale: :de]}

  """
  @spec parse_options(Keyword.t(), String.t()) :: {:ok, Keyword.t()} | {:error, Exception.t()}
  def parse_options(options, pattern) when is_list(options) and is_binary(pattern) do
    with :ok <- validate_options(options) do
      parse_options =
        options
        |> Keyword.drop([:format | @preferred_options])
        |> Keyword.put(:format, pattern)

      {:ok, parse_options}
    end
  end

  def parse_options(options, pattern) when is_list(options) do
    {:error, Localize.Utils.Helpers.invalid_value(pattern, "a date and time pattern string")}
  end

  def parse_options(options, _pattern) do
    {:error, Localize.Utils.Helpers.invalid_options(options)}
  end

  # The format must be UTF-8, which `translate_rest/6` reads it as, and
  # the options a keyword list.
  defp validate_format(format) do
    if String.valid?(format) do
      :ok
    else
      {:error, Localize.Utils.Helpers.invalid_value(format, "a UTF-8 strftime format string")}
    end
  end

  defp validate_options(options) do
    if Keyword.keyword?(options) do
      :ok
    else
      {:error, Localize.Utils.Helpers.invalid_options(options)}
    end
  end

  # The whole format is carried for the error, and `nested?` is true while
  # a preferred format is translated, where `%c`, `%x` and `%X` would
  # recurse without end.
  defp translate(format, rest, options, nested?) do
    case translate_rest(rest, format, options, nested?, [], []) do
      {:ok, pieces} -> {:ok, pieces |> Enum.reverse() |> IO.iodata_to_binary()}
      {:error, _reason} = error -> error
    end
  end

  defp translate_rest(<<>>, _format, _options, _nested?, literal, pieces) do
    {:ok, flush(literal, pieces)}
  end

  defp translate_rest(<<?%, rest::binary>>, format, options, nested?, literal, pieces) do
    pieces = flush(literal, pieces)
    {spec, rest} = directive(rest)

    with {:ok, piece} <- field(spec, format, options, nested?) do
      translate_rest(rest, format, options, nested?, [], [piece | pieces])
    end
  end

  defp translate_rest(<<char::utf8, rest::binary>>, format, options, nested?, literal, pieces) do
    translate_rest(rest, format, options, nested?, [<<char::utf8>> | literal], pieces)
  end

  # The directive after a `%`, past any padding and width, as the string
  # the error names: "%V", "%-d", or "%" alone at the end of the format.
  defp directive(rest) do
    {modifiers, rest} = modifiers(rest, [])

    case rest do
      <<letter::utf8, rest::binary>> -> {{letter, "%" <> modifiers <> <<letter::utf8>>}, rest}
      <<>> -> {{nil, "%" <> modifiers}, <<>>}
    end
  end

  defp modifiers(<<char, rest::binary>>, acc) when char in @padding or char in ?1..?9 do
    modifiers_digits(rest, [char | acc])
  end

  defp modifiers(rest, acc) do
    {acc |> Enum.reverse() |> List.to_string(), rest}
  end

  defp modifiers_digits(<<char, rest::binary>>, acc) when char in ?0..?9 do
    modifiers_digits(rest, [char | acc])
  end

  defp modifiers_digits(rest, acc) do
    {acc |> Enum.reverse() |> List.to_string(), rest}
  end

  defp field({?%, _written}, _format, _options, _nested?) do
    {:ok, "%"}
  end

  defp field({letter, _written}, _format, _options, _nested?)
       when letter in @whitespace_directives do
    {:ok, " "}
  end

  defp field({letter, _written}, _format, _options, _nested?)
       when is_map_key(@directives, letter) do
    {:ok, Map.fetch!(@directives, letter)}
  end

  defp field({letter, written}, format, options, nested?) when is_map_key(@preferred, letter) do
    if nested? do
      {:error, unsupported(format, written <> " inside a preferred format")}
    else
      {option, default} = Map.fetch!(@preferred, letter)
      preferred_pattern(Keyword.get(options, option, default), option, format, options)
    end
  end

  defp field({_letter, written}, format, _options, _nested?) do
    {:error, unsupported(format, written)}
  end

  defp preferred_pattern(preferred, option, format, options) when is_binary(preferred) do
    if String.valid?(preferred) do
      translate(format, preferred, options, true)
    else
      invalid_preferred(preferred, option)
    end
  end

  defp preferred_pattern(preferred, option, _format, _options) do
    invalid_preferred(preferred, option)
  end

  defp invalid_preferred(preferred, option) do
    {:error,
     Localize.Utils.Helpers.invalid_value(preferred, "a strftime format for #{inspect(option)}")}
  end

  # Literal text goes into the pattern as it is, quoted when it holds a
  # letter, which a pattern would otherwise read as a field, or a quote,
  # which is doubled inside the quotes as CLDR writes one. Whitespace at
  # either end stays outside the quotes, where the parsers read any run
  # of whitespace for it.
  defp flush([], pieces) do
    pieces
  end

  defp flush(literal, pieces) do
    text = literal |> Enum.reverse() |> IO.iodata_to_binary()

    if text =~ ~r/[A-Za-z']/ do
      [leading, core, trailing] =
        Regex.run(~r/\A(\s*)(.*?)(\s*)\z/s, text, capture: :all_but_first)

      [leading <> "'" <> String.replace(core, "'", "''") <> "'" <> trailing | pieces]
    else
      [text | pieces]
    end
  end

  defp unsupported(format, detail) do
    Localize.DateTimeFormatError.exception(
      format: format,
      reason: :unsupported_directive,
      detail: detail
    )
  end
end
