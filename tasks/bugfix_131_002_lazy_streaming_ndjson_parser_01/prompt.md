# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

# Lazy Streaming NDJSON Parser

Write me an Elixir module called `NdjsonStreamer` that parses a **very large
NDJSON file** (newline-delimited JSON — think gigabytes) by exposing it as a
**lazy stream** of decoded values. The whole point is composability: the caller
gets back a normal Elixir `Stream` they can pipe through `Stream`/`Enum`
functions, and nothing is read from disk until (and only as far as) the caller
actually consumes it.

## Public API

Implement two public functions:

```elixir
NdjsonStreamer.stream(file_path)   # => a lazy Enumerable
NdjsonStreamer.decode_line(line)   # => {:ok, value} | {:error, {:invalid_json, raw}}
```

- `stream/1` returns a **lazy** `Enumerable` (do not eagerly read the file, do
  not build a list). Enumerating it yields, in file order, one result per
  **non-blank** line:
  - `{:ok, value}` for a line that decodes as a single JSON value, or
  - `{:error, {:invalid_json, raw_line}}` for a malformed line, where `raw_line`
    is the trimmed line text.
- `decode_line/1` decodes a single trimmed line and returns the same
  `{:ok, value}` / `{:error, {:invalid_json, raw}}` shape. It must never raise
  on malformed input.

## Input file format

The file is **NDJSON**: one complete JSON value per line. There are **no**
array brackets, and **no** trailing commas — every line stands alone:

```
{"id":1,"value":"a"}
{"id":2,"value":"b"}

{"id":3,"value":"c"}
```

For each line:

1. Trim surrounding whitespace.
2. Skip the line entirely if it is empty after trimming (blank lines produce
   **no** element in the stream — not an `{:ok, _}` and not an `{:error, _}`).
3. Decode the remaining text as a single JSON value.

Use the standard library `JSON` module (Elixir 1.18+) for decoding, so JSON
objects become maps with **string keys** (e.g. `%{"id" => 1, "value" => "a"}`).

## Error handling (malformed lines)

A malformed line does **not** abort the stream. It surfaces as an inline
`{:error, {:invalid_json, raw_line}}` element and enumeration continues with the
next line. This lets the caller decide what to do (filter them out, log them,
count them) rather than the parser deciding for them.

## Memory constraints

Because the returned stream is lazy and line-based, memory must stay roughly
constant regardless of file size — do **not** read the whole file into a binary
or build a list of all items. Read the file lazily with `File.stream!/2`
(line-based) so that, at any moment, only a single line (plus its decoded value)
is in memory. A caller doing `stream(path) |> Stream.take(3) |> Enum.to_list()`
must not force the entire file.

## Constraints

- Use only the Elixir/OTP standard library. No external dependencies.
- Provide the complete module in a single file.

## The buggy module

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
    |> Stream.map(&String.trim/2)
    |> Stream.reject(&(&1 == ""))
    |> Stream.map(&decode_line/1)
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

## Failing test report

```
10 of 11 test(s) failed:

  * test stream/1 returns a lazy enumerable, not a list
      no function clause matching in Stream.map/2

  * test composes with Stream.take without forcing the whole file
      no function clause matching in Stream.map/2

  * test yields {:ok, value} for every well-formed line
      no function clause matching in Stream.map/2

  * test decodes objects into string-keyed maps
      no function clause matching in Stream.map/2

  (…6 more)
```
