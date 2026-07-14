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

# Parallel Streaming JSON Array Parser

Write me an Elixir module called `ParallelJsonStreamer` that parses a **very
large JSON array file** (think gigabytes) by **streaming** it, but decodes lines
**concurrently** across schedulers with a bounded concurrency window — while
still invoking the caller's handler for each item **in original file order**.

## Public API

Implement a single public function:

```elixir
ParallelJsonStreamer.process(file_path, handler_fn, opts \\ [])
```

- `file_path` is the path to a file on disk.
- `handler_fn` is a one-arity function. For every successfully decoded item, you
  call `handler_fn.(item)` **exactly once**, and these calls must happen in the
  **same order the items appear in the file** (even though decoding runs
  concurrently). Its return value is ignored.
- `opts` may contain `:max_concurrency` (positive integer). Default it to
  `System.schedulers_online()`. At most this many lines may be decoded
  concurrently at any instant.
- The function returns `{:ok, stats}` where `stats` is a map with these keys:

  - `:processed` — integer, how many items were successfully decoded and passed
    to `handler_fn`.
  - `:errors` — integer, how many items were malformed and skipped.
  - `:elapsed_ms` — number, wall-clock time spent processing (use
    `System.monotonic_time/1`). Must be `>= 0`.
  - `:throughput` — float, processed items per second
    (`processed / (elapsed_ms / 1000)`). If `elapsed_ms` is `0`, return `0.0`
    (never divide by zero).
  - `:max_concurrency` — the effective concurrency limit used.

## Input file format

Same one-element-per-line JSON array layout as the classic streamer:

```
[
{"id":1,"value":"a"},
{"id":2,"value":"b"},
{"id":3,"value":"c"}
]
```

- The first line is `[` on its own; the last line is `]` on its own.
- Every element line ends with a trailing comma `,` except the last element
  line. An empty array is `[` then `]`.

For each line: trim whitespace; skip if empty, `[`, or `]`; strip a single
trailing comma if present; decode the remainder as one JSON value with the
standard library `JSON` module (Elixir 1.18+), so objects become maps with
**string keys**.

## Concurrency requirement

Decoding must run in parallel with a bounded window (use `Task.async_stream`
with `max_concurrency:` and `ordered: true`, or an equivalent). The observable
contract is:

- No more than `:max_concurrency` decode tasks run at once.
- `handler_fn` is still called **exactly once per successful item, in file
  order** — concurrency must not reorder or duplicate handler calls.

## Error handling (malformed items)

A malformed line is counted in `:errors`, **skipped**, and must **not** invoke
`handler_fn`. A malformed entry anywhere in the stream must not abort processing
and must not disturb the ordering of the successful items around it.

## Memory constraints

Memory must stay roughly constant regardless of file size — read lazily with
`File.stream!/2` and only keep a bounded window (proportional to
`:max_concurrency`) in flight. Do not read the whole file into memory or build a
list of all items.

## Constraints

- Use only the Elixir/OTP standard library. No external dependencies.
- Provide the complete module in a single file.
