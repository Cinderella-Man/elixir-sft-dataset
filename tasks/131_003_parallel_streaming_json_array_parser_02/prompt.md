# Fill in the middle: `ParallelJsonStreamer.process/3`

Implement the public `process/3` function. It streams a very large JSON array
file lazily, decodes element lines concurrently within a bounded concurrency
window, and invokes the caller's `handler_fn` exactly once per successfully
decoded item **in original file order**, then returns `{:ok, stats}`.

Specifically, `process/3` must:

- Accept `file_path`, a one-arity `handler_fn`, and `opts` (defaulting to `[]`).
  Guard that `handler_fn` is a function of arity 1.
- Read `:max_concurrency` from `opts`, defaulting to
  `System.schedulers_online()`.
- Record a start timestamp with `System.monotonic_time(:microsecond)`.
- Build a lazy pipeline over the file:
  - `File.stream!(file_path, [], :line)` to read line by line without loading
    the whole file.
  - `Stream.map/2` with `String.trim/1` to trim each line.
  - `Stream.reject/2` to drop lines that are `""`, `"["`, or `"]"`.
  - `Task.async_stream/3` calling the private `decode_line/1` with
    `max_concurrency: max_concurrency` and `ordered: true`, so decoding runs in
    parallel but results are consumed in file order.
- Reduce the async-stream results with `Enum.reduce/3` over an accumulator
  `{processed, errors}` starting at `{0, 0}`:
  - On `{:ok, {:ok, item}}`, call `handler_fn.(item)` and increment `processed`.
  - On `{:ok, {:error, _reason}}`, increment `errors` and do not call the
    handler.
- Compute `elapsed_us` from the monotonic clock and derive
  `elapsed_ms = max(elapsed_us / 1000, 0)`.
- Assemble and return `{:ok, stats}` where `stats` is a map with keys
  `:processed`, `:errors`, `:elapsed_ms`, `:throughput` (via the private
  `throughput/2` helper), and `:max_concurrency`.

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
    # TODO
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
  defp throughput(_processed, +0.0), do: 0.0
  defp throughput(_processed, 0), do: 0.0
  defp throughput(processed, elapsed_ms), do: processed / (elapsed_ms / 1000)
end
```