# Lazy Streaming NDJSON Parser — implement `decode_line/1`

Implement the public `decode_line/1` function. It takes a single line of text and
decodes it into a single JSON value, returning the same result shape used
throughout the module: `{:ok, value}` on success or
`{:error, {:invalid_json, raw}}` on failure. It must **never raise** on malformed
input.

Specifically, it should:

1. Trim surrounding whitespace from the incoming `line`.
2. Attempt to decode the trimmed text as a single JSON value using the standard
   library `JSON` module (Elixir 1.18+), so JSON objects become maps with
   **string keys** (e.g. `%{"id" => 1, "value" => "a"}`).
3. On a successful decode, return `{:ok, value}`.
4. On a decode failure, return `{:error, {:invalid_json, raw}}`, where `raw` is
   the **trimmed** line text (not the original untrimmed input).

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
    file_path
    |> File.stream!(:line, [])
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == ""))
    |> Stream.map(&decode_line/1)
  end

  @doc """
  Decodes a single line, returning `{:ok, value}` or
  `{:error, {:invalid_json, raw}}`. Never raises on malformed input.
  """
  @spec decode_line(String.t()) :: result()
  def decode_line(line) do
    # TODO
  end
end
```