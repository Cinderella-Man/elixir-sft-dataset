# Implement `process/3`

Implement the public `process/3` function — the single entry point of
`ResumableJsonStreamer`. It has the signature
`process(file_path, handler_fn, opts \\ [])` and is guarded by
`is_function(handler_fn, 1)`.

The function must:

1. Read `opts`: `:max_errors` (default `:infinity`) and `:resume_from`
   (default `0`), via `Keyword.get/3`.
2. Record a start timestamp with `System.monotonic_time(:microsecond)`.
3. Build the initial accumulator
   `%{processed: 0, errors: 0, index: 0, aborted: false}`.
4. Stream `file_path` lazily with `File.stream!(file_path, [], :line)`, trim each
   line with `String.trim/1`, reject the lines `""`, `"["`, and `"]"` (so only
   element lines remain), and fold with `Enum.reduce_while/3`. For each element
   line, bump the accumulator's `:index` by 1 and delegate the decision to the
   private `step/5` helper, passing `handler_fn`, `resume_from`, and
   `max_errors`. Because it reduces while, an abort halts reading immediately and
   the rest of the file is never consumed.
5. After the fold, compute elapsed microseconds from the start timestamp, convert
   to milliseconds as `max(elapsed_us / 1000, 0)`.
6. Assemble the `stats` map with `:processed`, `:errors` from the fold result,
   `:elapsed_ms`, `:throughput` (via the private `throughput/2` helper),
   `:last_index` (the fold's final `:index`), and `:aborted` (the fold's
   `:aborted` flag).
7. Return `{:error, :too_many_errors, stats}` when the run aborted, otherwise
   `{:ok, stats}`.

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
    # TODO
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