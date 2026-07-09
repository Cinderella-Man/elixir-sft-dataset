# Implement `step/5`

Implement the private `step/5` function, the reducer body folded over every
**element line** of the file by `Enum.reduce_while/3`. It receives the trimmed
`line`, the accumulator `acc` (a map with `:processed`, `:errors`, `:index`, and
`:aborted`, whose `:index` has *already* been incremented to reflect the current
element line), the caller's `handler_fn`, the `resume_from` cutoff, and the
`max_errors` budget. It must return `{:cont, acc}` to keep streaming or
`{:halt, acc}` to abort and stop reading the rest of the file.

Its behavior:

- **Resume skip.** If the current element's `acc.index` is `<= resume_from`, the
  line has already been processed (or is being skipped past): do not decode it,
  do not call `handler_fn`, and do not touch `:processed` or `:errors`. Just
  return `{:cont, acc}` unchanged.
- **Otherwise decode.** Decode the line with `decode_line/1`.
  - On `{:ok, item}`: invoke `handler_fn.(item)` exactly once (its return value
    is ignored), increment `:processed`, and return `{:cont, ...}`.
  - On `{:error, _reason}`: increment `:errors`. Then, if the new error count
    exceeds the budget (use `exceeds?/2` with `max_errors`), mark the
    accumulator `aborted: true` and return `{:halt, ...}` so the fold stops
    immediately. Otherwise return `{:cont, ...}` with the bumped error count.

Because the accumulator's `:index` already points at the current line, halting on
a poison line leaves `:index` on that line, which is what makes
`resume_from: last_index` resume *past* it. Prefer expressing the resume-skip
case as its own guarded function clause.

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
  defp step(line, acc, handler_fn, resume_from, max_errors) do
    # TODO
  end

  @spec exceeds?(non_neg_integer(), non_neg_integer() | :infinity) :: boolean()
  defp exceeds?(_errors, :infinity), do: false
  defp exceeds?(errors, max) when is_integer(max), do: errors > max

  @spec decode_line(String.t()) :: {:ok, term()} | {:error, term()}
  defp decode_line(trimmed) do
    trimmed
    |> strip_trailing_comma()
    |> JSON.decode()
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