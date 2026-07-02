# Lazy Streaming NDJSON Parser — implement `stream/1`

You are given the complete `NdjsonStreamer` module below, except that the body of
the public `stream/1` function has been removed and replaced with `# TODO`. Your
job is to implement `stream/1`.

Implement the public `stream/1` function. It takes a `file_path` and returns a
**lazy** `Enumerable` yielding one result per **non-blank** line of the NDJSON
file, in file order. Read the file lazily with `File.stream!/2` in `:line` mode so
that only a single line is ever in memory — do not read the whole file into a
binary and do not build a list. Trim each line's surrounding whitespace with
`String.trim/1`, drop any line that is empty after trimming (blank lines must
produce no element at all — neither `{:ok, _}` nor `{:error, _}`), and map each
remaining line through `decode_line/1` so it becomes `{:ok, value}` or
`{:error, {:invalid_json, raw}}`. Build the pipeline entirely from `Stream`
combinators (`Stream.map/2`, `Stream.reject/2`) so nothing is read from disk
until (and only as far as) the returned stream is consumed.

```elixir
defmodule NdjsonStreamer do
  @moduledoc """
  Lazy streaming parser for very large NDJSON (newline-delimited JSON) files.

  Unlike an eager parser that folds over the file and calls a handler,
  `stream/1` returns a plain lazy `Enumerable`. Callers compose it with
  `Stream`/`Enum` functions and decide themselves what to do with malformed
  lines, which surface inline as `{:error, {:invalid_json, raw}}` elements.

  The file is read lazily with `File.stream!/2`, so only a single line (plus its
  decoded value) is ever in memory, regardless of file size.

  Expected layout — one complete JSON value per line, no brackets, no commas:

      {"id":1,"value":"a"}
      {"id":2,"value":"b"}
      {"id":3,"value":"c"}
  """

  @type result :: {:ok, term()} | {:error, {:invalid_json, String.t()}}

  @doc """
  Returns a lazy enumerable yielding one `t:result/0` per non-blank line.

  Blank lines (empty after trimming) are dropped and produce no element.
  Nothing is read from disk until the returned stream is enumerated, and only
  as far as it is consumed.
  """
  @spec stream(Path.t()) :: Enumerable.t()
  def stream(file_path) do
    # TODO
  end

  @doc """
  Decodes a single line, returning `{:ok, value}` or
  `{:error, {:invalid_json, raw}}`. Never raises on malformed input.
  """
  @spec decode_line(String.t()) :: result()
  def decode_line(line) do
    trimmed = String.trim(line)

    case JSON.decode(trimmed) do
      {:ok, value} -> {:ok, value}
      {:error, _reason} -> {:error, {:invalid_json, trimmed}}
    end
  end
end
```