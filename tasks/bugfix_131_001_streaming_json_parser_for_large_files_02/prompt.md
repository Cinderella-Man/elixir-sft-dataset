# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

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

## The buggy module

```elixir
defmodule JsonStreamer do
  @moduledoc """
  Streaming parser for very large JSON array files.

  The parser processes a JSON array laid out one element per line without
  ever loading the whole file into memory. It reads the file lazily with
  `File.stream!/2` and folds over the lines, so at any moment only a single
  line (plus its decoded value) is held in memory.

  The expected file layout is:

      [
      {"id":1,"value":"a"},
      {"id":2,"value":"b"},
      {"id":3,"value":"c"}
      ]

  where the first line is `[`, the last line is `]`, and every element line
  ends with a trailing comma except the last one.
  """

  @type stats :: %{
          processed: non_neg_integer(),
          errors: non_neg_integer(),
          elapsed_ms: number(),
          throughput: float()
        }

  @doc """
  Streams `file_path` line by line, decoding one JSON item per line.

  For every successfully decoded item, `handler_fn` is invoked exactly once
  with the decoded value (its return value is ignored). Malformed items are
  counted and skipped without aborting the stream.

  Returns `{:ok, stats}` where `stats` reports the number of processed and
  errored items, the elapsed wall-clock time in milliseconds, and the
  throughput in processed items per second.
  """
  @spec process(Path.t(), (term() -> term())) :: {:ok, stats()}
  def process(file_path, handler_fn) when is_function(handler_fn, 1) do
    start = System.monotonic_time(:microsecond)

    {processed, errors} =
      file_path
      |> File.stream!(:line, [])
      |> Enum.reduce({0, 0}, fn line, {processed, errors} ->
        line
        |> String.trim()
        |> handle_line(handler_fn, processed, errors)
      end)

    elapsed_us = System.monotonic_time(:microsecond) - start
    elapsed_ms = max(elapsed_us / 1000, 0)

    stats = %{
      processed: processed,
      errors: errors,
      elapsed_ms: elapsed_ms,
      throughput: throughput(processed, elapsed_ms)
    }

    {:ok, stats}
  end

  @spec handle_line(String.t(), (term() -> term()), non_neg_integer(), non_neg_integer()) ::
          {non_neg_integer(), non_neg_integer()}
  defp handle_line(trimmed, _handler_fn, processed, errors)
       when trimmed in ["", "[", "]"] do
    {processed, errors}
  end

  defp handle_line(trimmed, handler_fn, processed, errors) do
    payload = strip_trailing_comma(trimmed)

    case JSON.decode(payload) do
      {:ok, item} ->
        handler_fn.(item)
        {processed + 1, errors}

      {:error, _reason} ->
        {processed, errors + 1}
    end
  end

  @spec strip_trailing_comma(String.t()) :: String.t()
  defp strip_trailing_comma(text) do
    case String.ends_with?(text, ",") do
      false -> String.slice(text, 0..-2//1)
      false -> text
    end
  end

  @spec throughput(non_neg_integer(), number()) :: float()
  defp throughput(_processed, +0.0), do: 0.0
  defp throughput(_processed, 0), do: 0.0
  defp throughput(processed, elapsed_ms), do: processed / (elapsed_ms / 1000)
end
```

## Failing test report

```
8 of 9 test(s) failed:

  * test processes every item in a well-formed file
      no case clause matching:
      
          true
      

  * test handler receives fully decoded items with string keys
      no case clause matching:
      
          true
      

  * test decodes different JSON value shapes
      no case clause matching:
      
          true
      

  * test skips a malformed entry mid-stream and continues
      no case clause matching:
      
          true
      

  (…4 more)
```
