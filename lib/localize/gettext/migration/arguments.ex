defmodule Localize.Gettext.Migration.Arguments do
  @moduledoc false

  # Finds the arguments of a call in source text: from the byte after its
  # opening parenthesis to the matching closing one, split at the commas
  # outside any bracket, string, heredoc, sigil or comment. It reads text,
  # not Elixir syntax, so it serves a call in a HEEx template as well as in
  # a module.

  @openers ~c"([{"
  @closers ~c")]}"
  @sigil_pairs %{?( => ?), ?[ => ?], ?{ => ?}, ?< => ?>}
  @sigil_delimiters ~c"([{</|\"'"

  @doc false
  # The argument spans of the call whose opening parenthesis is at
  # `open`, as `{start, stop}` byte offsets, stop exclusive, or `:error`
  # where the text ends first.
  @spec spans(String.t(), non_neg_integer()) ::
          {:ok, [{non_neg_integer(), non_neg_integer()}]} | :error
  def spans(source, open) when is_binary(source) and open < byte_size(source) do
    start = open + 1
    rest = binary_part(source, start, byte_size(source) - start)
    scan(rest, start, 0, start, [])
  end

  def spans(_source, _open) do
    :error
  end

  defp scan(<<>>, _position, _depth, _argument_start, _spans) do
    :error
  end

  defp scan(<<?), _rest::binary>>, position, 0, argument_start, spans) do
    {:ok, Enum.reverse([{argument_start, position} | spans])}
  end

  defp scan(<<?,, rest::binary>>, position, 0, argument_start, spans) do
    scan(rest, position + 1, 0, position + 1, [{argument_start, position} | spans])
  end

  defp scan(<<byte, rest::binary>>, position, depth, argument_start, spans)
       when byte in @openers do
    scan(rest, position + 1, depth + 1, argument_start, spans)
  end

  defp scan(<<byte, rest::binary>>, position, depth, argument_start, spans)
       when byte in @closers do
    scan(rest, position + 1, depth - 1, argument_start, spans)
  end

  defp scan(<<"\"\"\"", rest::binary>>, position, depth, argument_start, spans) do
    rest
    |> skip_until("\"\"\"", position + 3)
    |> continue(depth, argument_start, spans)
  end

  defp scan(<<"'''", rest::binary>>, position, depth, argument_start, spans) do
    rest
    |> skip_until("'''", position + 3)
    |> continue(depth, argument_start, spans)
  end

  defp scan(<<quote, rest::binary>>, position, depth, argument_start, spans)
       when quote in ~c"\"'" do
    rest
    |> skip_until(<<quote>>, position + 1)
    |> continue(depth, argument_start, spans)
  end

  defp scan(<<?~, letter, rest::binary>>, position, depth, argument_start, spans)
       when letter in ?a..?z or letter in ?A..?Z do
    rest
    |> skip_sigil(position + 2)
    |> continue(depth, argument_start, spans)
  end

  # A character literal such as `?(` or `?,` is not a delimiter.
  defp scan(<<??, byte, rest::binary>>, position, depth, argument_start, spans)
       when byte in ~c"()[]{},\"'#" do
    scan(rest, position + 2, depth, argument_start, spans)
  end

  defp scan(<<?#, rest::binary>>, position, depth, argument_start, spans) do
    rest
    |> skip_comment(position + 1)
    |> continue(depth, argument_start, spans)
  end

  defp scan(<<_byte, rest::binary>>, position, depth, argument_start, spans) do
    scan(rest, position + 1, depth, argument_start, spans)
  end

  defp continue({:ok, rest, position}, depth, argument_start, spans) do
    scan(rest, position, depth, argument_start, spans)
  end

  defp continue(:error, _depth, _argument_start, _spans) do
    :error
  end

  # Skips to just after `closing`, past escapes and `#{…}` interpolations.
  defp skip_until(<<>>, _closing, _position) do
    :error
  end

  defp skip_until(<<?\\, escaped::utf8, rest::binary>>, closing, position) do
    skip_until(rest, closing, position + 1 + byte_size(<<escaped::utf8>>))
  end

  defp skip_until(<<"\#{", rest::binary>>, closing, position) do
    case skip_interpolation(rest, position + 2, 0) do
      {:ok, rest, position} -> skip_until(rest, closing, position)
      :error -> :error
    end
  end

  defp skip_until(<<_byte, rest::binary>> = binary, closing, position) do
    if String.starts_with?(binary, closing) do
      size = byte_size(closing)
      {:ok, binary_part(binary, size, byte_size(binary) - size), position + size}
    else
      skip_until(rest, closing, position + 1)
    end
  end

  defp skip_interpolation(<<>>, _position, _depth) do
    :error
  end

  defp skip_interpolation(<<?}, rest::binary>>, position, 0) do
    {:ok, rest, position + 1}
  end

  defp skip_interpolation(<<?}, rest::binary>>, position, depth) do
    skip_interpolation(rest, position + 1, depth - 1)
  end

  defp skip_interpolation(<<?{, rest::binary>>, position, depth) do
    skip_interpolation(rest, position + 1, depth + 1)
  end

  defp skip_interpolation(<<quote, rest::binary>>, position, depth) when quote in ~c"\"'" do
    case skip_until(rest, <<quote>>, position + 1) do
      {:ok, rest, position} -> skip_interpolation(rest, position, depth)
      :error -> :error
    end
  end

  defp skip_interpolation(<<_byte, rest::binary>>, position, depth) do
    skip_interpolation(rest, position + 1, depth)
  end

  # A sigil's further letters, then its delimiter, which is a heredoc's or
  # a single character closed by itself or by its pair.
  defp skip_sigil(<<letter, rest::binary>>, position) when letter in ?A..?Z do
    skip_sigil(rest, position + 1)
  end

  defp skip_sigil(<<"\"\"\"", rest::binary>>, position) do
    skip_until(rest, "\"\"\"", position + 3)
  end

  defp skip_sigil(<<"'''", rest::binary>>, position) do
    skip_until(rest, "'''", position + 3)
  end

  defp skip_sigil(<<opening, rest::binary>>, position) when opening in @sigil_delimiters do
    closing = Map.get(@sigil_pairs, opening, opening)
    skip_until(rest, <<closing>>, position + 1)
  end

  defp skip_sigil(rest, position) do
    {:ok, rest, position}
  end

  defp skip_comment(<<>>, position) do
    {:ok, <<>>, position}
  end

  defp skip_comment(<<?\n, rest::binary>>, position) do
    {:ok, rest, position + 1}
  end

  defp skip_comment(<<_byte, rest::binary>>, position) do
    skip_comment(rest, position + 1)
  end
end
