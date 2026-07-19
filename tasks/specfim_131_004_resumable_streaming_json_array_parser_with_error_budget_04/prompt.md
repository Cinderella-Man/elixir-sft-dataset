# Write the missing @spec

Below is a complete, working module — except that the `@spec` for
`exceeds?/2` has been removed; its place is marked `# TODO: @spec`.
Write exactly that typespec: one `@spec` attribute for `exceeds?/2`,
consistent with the function's arguments, guards, and every return shape
the implementation can produce. Change nothing else.

## The module with the `@spec` for `exceeds?/2` missing

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

  # TODO: @spec
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

Give me only the `@spec` attribute — the attribute alone (however many
lines it spans), not the whole module.
