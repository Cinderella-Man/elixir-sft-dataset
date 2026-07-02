# Streaming JSON Array Parser

Write me an Elixir module called `JsonStreamer` that parses a **very large JSON
array file** (think gigabytes) by **streaming** it — processing one item at a
time and never loading the whole file into memory.

## Public API

Implement a single public function:

```elixir
JsonStreamer.process(file_path, handler_fn)
```

- `file_path` is the path to a file on disk.
- `handler_fn` is a one-arity function. For every successfully decoded item, you
  call `handler_fn.(item)` exactly once. Its return value is ignored.
- The function returns `{:ok, stats}` where `stats` is a map with these keys:

  - `:processed` — integer, how many items were successfully decoded and passed
    to `handler_fn`.
  - `:errors` — integer, how many items were malformed and skipped.
  - `:elapsed_ms` — number, wall-clock time spent processing (use
    `System.monotonic_time/1`). Must be `>= 0`.
  - `:throughput` — float, processed items per second
    (`processed / (elapsed_ms / 1000)`). If `elapsed_ms` is `0`, return `0.0`
    (never divide by zero).

## Input file format

The file represents a JSON array laid out one element per line:

```
[
{"id":1,"value":"a"},
{"id":2,"value":"b"},
{"id":3,"value":"c"}
]
```

- The first line is `[` on its own.
- Each element is on its own line. Every element line ends with a trailing comma
  `,` **except** the last element line, which has none.
- The last line is `]` on its own.
- An empty array is written as `[` on the first line and `]` on the second.

Your parser must process the file **line by line** and, for each line:

1. Trim surrounding whitespace.
2. Skip the line if it is empty, or is exactly `[`, or is exactly `]`.
3. Strip a single trailing comma if present.
4. Decode the remaining text as a single JSON value.

Use the standard library `JSON` module (Elixir 1.18+) for decoding, so JSON
objects become maps with **string keys** (e.g. `%{"id" => 1, "value" => "a"}`).

## Error handling (malformed items)

If decoding a line fails, that item is **malformed**: increment the `:errors`
count, **skip it**, and **continue streaming** the rest of the file. A malformed
entry in the middle of the stream must not abort processing and must not call
`handler_fn`.

## Memory constraints

Memory usage must stay roughly constant regardless of file size — do **not**
read the whole file into a binary or build a list of all items. Read the file
lazily with `File.stream!/2` (line-based) and fold over it so that, at any
moment, only a single line (plus its decoded value) is in memory.

## Constraints

- Use only the Elixir/OTP standard library. No external dependencies.
- Provide the complete module in a single file.