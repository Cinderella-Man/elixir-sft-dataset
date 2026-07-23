# Implement the missing function

Below you'll find a task's full specification, then a working, tested
solution with one gap: `strip_trailing_comma` — every clause body swapped for
`# TODO`. Rebuild exactly that function so the module passes the task's
whole suite again, and leave every other line precisely as shown.

## The task

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

## The module with `strip_trailing_comma` missing

```elixir
defmodule ParallelJsonStreamer do
  @moduledoc """
  Streaming parser for very large JSON array files that decodes lines
  concurrently across schedulers within a bounded concurrency window, while
  still invoking the caller's handler exactly once per item, in file order.

  Decoding is fanned out with `Task.async_stream/3` using `ordered: true`, so
  results are consumed back in the original order even though the CPU-bound
  `JSON.decode/1` work runs in parallel. The file is read lazily with
  `File.stream!/2` and only a window proportional to `:max_concurrency` is ever
  in flight, keeping memory roughly constant regardless of file size.
  """

  @type stats :: %{
          processed: non_neg_integer(),
          errors: non_neg_integer(),
          elapsed_ms: number(),
          throughput: float(),
          max_concurrency: pos_integer()
        }

  @doc """
  Streams `file_path`, decoding lines concurrently and calling `handler_fn` once
  per successfully decoded item in file order. Returns `{:ok, stats}`.
  """
  @spec process(Path.t(), (term() -> term()), keyword()) :: {:ok, stats()}
  def process(file_path, handler_fn, opts \\ []) when is_function(handler_fn, 1) do
    max_concurrency = Keyword.get(opts, :max_concurrency, System.schedulers_online())
    start = System.monotonic_time(:microsecond)

    {processed, errors} =
      file_path
      |> File.stream!(:line, [])
      |> Stream.map(&String.trim/1)
      |> Stream.reject(&(&1 in ["", "[", "]"]))
      |> Task.async_stream(&decode_line/1,
        max_concurrency: max_concurrency,
        ordered: true
      )
      |> Enum.reduce({0, 0}, fn
        {:ok, {:ok, item}}, {p, e} ->
          handler_fn.(item)
          {p + 1, e}

        {:ok, {:error, _reason}}, {p, e} ->
          {p, e + 1}
      end)

    elapsed_us = System.monotonic_time(:microsecond) - start
    elapsed_ms = max(elapsed_us / 1000, 0)

    stats = %{
      processed: processed,
      errors: errors,
      elapsed_ms: elapsed_ms,
      throughput: throughput(processed, elapsed_ms),
      max_concurrency: max_concurrency
    }

    {:ok, stats}
  end

  @spec decode_line(String.t()) :: {:ok, term()} | {:error, term()}
  defp decode_line(trimmed) do
    trimmed
    |> strip_trailing_comma()
    |> JSON.decode()
  end

  defp strip_trailing_comma(text) do
    # TODO
  end

  @spec throughput(non_neg_integer(), number()) :: float()
  defp throughput(_processed, +0.0), do: 0.0
  defp throughput(_processed, 0), do: 0.0
  defp throughput(processed, elapsed_ms), do: processed / (elapsed_ms / 1000)
end
```

Reply with `strip_trailing_comma` alone (bring along any `@doc`/`@spec`/`@impl` lines
that belong directly above it) — just the function, never the whole
module.
