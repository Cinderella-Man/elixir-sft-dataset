# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `decode_line` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

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

## The module with `decode_line` missing

```elixir
defmodule ResumableJsonStreamer do
  @moduledoc """
  Streaming parser for very large JSON array files with strict failure
  semantics: a per-run error budget (`:max_errors`) that aborts the stream once
  too many items are malformed, and resumable processing (`:resume_from`) that
  skips already-processed (or poison) element lines.

  Only **element lines** (not blank, not `[`, not `]`) count toward indexing;
  they are numbered `1, 2, 3, …` in file order. On an abort, `:last_index` points
  at the offending line, so a re-run with `resume_from: last_index` continues
  past it.

  The file is read lazily with `File.stream!/2` and folded with
  `Enum.reduce_while/3`, so only a single line is ever in memory and an abort
  stops reading the rest of the file immediately.
  """

  @type stats :: %{
          processed: non_neg_integer(),
          errors: non_neg_integer(),
          elapsed_ms: number(),
          throughput: float(),
          last_index: non_neg_integer(),
          aborted: boolean()
        }

  @doc """
  Streams `file_path`, honoring `:max_errors` and `:resume_from`. Returns
  `{:ok, stats}` on a clean run or `{:error, :too_many_errors, stats}` on abort.
  """
  @spec process(Path.t(), (term() -> term()), keyword()) ::
          {:ok, stats()} | {:error, :too_many_errors, stats()}
  def process(file_path, handler_fn, opts \\ []) when is_function(handler_fn, 1) do
    max_errors = Keyword.get(opts, :max_errors, :infinity)
    resume_from = Keyword.get(opts, :resume_from, 0)
    start = System.monotonic_time(:microsecond)

    init = %{processed: 0, errors: 0, index: 0, aborted: false}

    result =
      file_path
      |> File.stream!(:line, [])
      |> Stream.map(&String.trim/1)
      |> Stream.reject(&(&1 in ["", "[", "]"]))
      |> Enum.reduce_while(init, fn line, acc ->
        step(line, %{acc | index: acc.index + 1}, handler_fn, resume_from, max_errors)
      end)

    elapsed_us = System.monotonic_time(:microsecond) - start
    elapsed_ms = max(elapsed_us / 1000, 0)

    stats = %{
      processed: result.processed,
      errors: result.errors,
      elapsed_ms: elapsed_ms,
      throughput: throughput(result.processed, elapsed_ms),
      last_index: result.index,
      aborted: result.aborted
    }

    if result.aborted do
      {:error, :too_many_errors, stats}
    else
      {:ok, stats}
    end
  end

  @spec step(
          String.t(),
          map(),
          (term() -> term()),
          non_neg_integer(),
          non_neg_integer() | :infinity
        ) ::
          {:cont, map()} | {:halt, map()}
  defp step(_line, %{index: index} = acc, _handler_fn, resume_from, _max_errors)
       when index <= resume_from do
    {:cont, acc}
  end

  defp step(line, acc, handler_fn, _resume_from, max_errors) do
    case decode_line(line) do
      {:ok, item} ->
        handler_fn.(item)
        {:cont, %{acc | processed: acc.processed + 1}}

      {:error, _reason} ->
        errors = acc.errors + 1
        acc = %{acc | errors: errors}

        if exceeds?(errors, max_errors) do
          {:halt, %{acc | aborted: true}}
        else
          {:cont, acc}
        end
    end
  end

  @spec exceeds?(non_neg_integer(), non_neg_integer() | :infinity) :: boolean()
  defp exceeds?(_errors, :infinity), do: false
  defp exceeds?(errors, max) when is_integer(max), do: errors > max

  defp decode_line(trimmed) do
    # TODO
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

Give me only the complete implementation of `decode_line` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
