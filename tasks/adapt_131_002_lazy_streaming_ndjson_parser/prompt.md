# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

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
      true -> String.slice(text, 0..-2//1)
      false -> text
    end
  end

  @spec throughput(non_neg_integer(), number()) :: float()
  defp throughput(_processed, +0.0), do: 0.0
  defp throughput(_processed, 0), do: 0.0
  defp throughput(processed, elapsed_ms), do: processed / (elapsed_ms / 1000)
end
```

## New specification

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
