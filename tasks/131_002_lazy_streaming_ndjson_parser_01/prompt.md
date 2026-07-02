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