# Fill in the middle: `throughput/2`

Implement the private `throughput/2` helper for `ParallelJsonStreamer`. It
computes the processing rate in **items per second** from a count of successfully
processed items and the elapsed wall-clock time in milliseconds.

- It takes two arguments: `processed` (a non-negative integer) and `elapsed_ms`
  (a number of milliseconds, which may be an integer or a float).
- It must **never divide by zero**: when `elapsed_ms` is zero — whether that is
  the integer `0` or the float `+0.0` — return `0.0`.
- Otherwise, convert `elapsed_ms` to seconds and return
  `processed / (elapsed_ms / 1000)` as a float (items per second).

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

  @spec strip_trailing_comma(String.t()) :: String.t()
  defp strip_trailing_comma(text) do
    case String.ends_with?(text, ",") do
      true -> String.slice(text, 0..-2//1)
      false -> text
    end
  end

  @spec throughput(non_neg_integer(), number()) :: float()
  defp throughput(_processed, +0.0) do
    # TODO
  end
end

```