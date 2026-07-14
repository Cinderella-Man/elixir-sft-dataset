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

# Resumable Streaming JSON Array Parser with Error Budget

Write me an Elixir module called `ResumableJsonStreamer` that streams a **very
large JSON array file** (think gigabytes) one item at a time, but with two
failure-semantics features the classic streamer lacks: a **strict error budget**
that aborts the run when too many items are malformed, and **resumable
processing** so a re-run can skip past already-processed (or poison) items.

## Public API

Implement a single public function:

```elixir
ResumableJsonStreamer.process(file_path, handler_fn, opts \\ [])
```

- `file_path` is the path to a file on disk.
- `handler_fn` is a one-arity function. For every successfully decoded item that
  is **not skipped by resume**, you call `handler_fn.(item)` exactly once. Its
  return value is ignored.
- `opts` may contain:
  - `:max_errors` — a non-negative integer, or `:infinity` (the default). This
    is the number of malformed items **tolerated**. The stream aborts on the
    error that would push the cumulative error count **above** `:max_errors`.
    So `max_errors: 0` aborts on the first malformed item; `max_errors: 2` keeps
    going through two malformed items and aborts on the third.
  - `:resume_from` — a non-negative integer (default `0`). Skip the first
    `:resume_from` **element lines** entirely: they are not decoded, not passed
    to `handler_fn`, and not counted in `:processed` or `:errors`.

## Element indexing

Only **element lines** count toward indexing: lines that are not blank, not `[`,
and not `]`. They are numbered `1, 2, 3, …` in file order. `:resume_from` skips
element lines whose index is `<= resume_from`. The returned `:last_index` is the
index of the last element line the parser examined.

## Return value

- On a clean run, return `{:ok, stats}`.
- On abort (error budget exceeded), return `{:error, :too_many_errors, stats}`.

`stats` is a map with:

- `:processed` — integer, items successfully decoded and passed to `handler_fn`.
- `:errors` — integer, malformed items encountered (up to and including the one
  that triggered an abort).
- `:elapsed_ms` — number, wall-clock time (use `System.monotonic_time/1`), `>= 0`.
- `:throughput` — float, `processed / (elapsed_ms / 1000)`; `0.0` when
  `elapsed_ms` is `0` (never divide by zero).
- `:last_index` — integer, the index of the last element line examined. Lines
  skipped by `resume_from` still count as examined, so `resume_from` past the end
  yields the total element count; `0` only when the array has no elements.
- `:aborted` — boolean, `true` iff the error budget was exceeded.

Because `:last_index` on an abort points at the poison line, a caller can resume
past it with `resume_from: last_index`.

## Input file format

Same one-element-per-line JSON array layout as the classic streamer: first line
`[`, last line `]`, every element line ending in a trailing comma except the
last; empty array is `[` then `]`. For each element line: trim whitespace, strip
a single trailing comma if present, and decode with the standard library `JSON`
module (Elixir 1.18+) so objects become maps with **string keys**.

## Memory constraints

Read lazily with `File.stream!/2` and fold so only a single line (plus its
decoded value) is in memory at a time. Aborting must stop reading early — do not
consume the rest of the file after the budget is blown.

## Constraints

- Use only the Elixir/OTP standard library. No external dependencies.
- Provide the complete module in a single file.
