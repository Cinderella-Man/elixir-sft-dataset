defmodule ParallelJsonStreamer do
  @moduledoc """
  Streams a very large JSON array file (one element per line) from disk and decodes the
  element lines concurrently, while still invoking the caller's handler for each decoded
  item in the original file order.

  ## Expected file layout

      [
      {"id":1,"value":"a"},
      {"id":2,"value":"b"},
      {"id":3,"value":"c"}
      ]

  The first line is `[` on its own, the last line is `]` on its own, and every element line
  carries a trailing comma except the final one. An empty array is `[` followed by `]`.

  ## Design

  * The file is read lazily with `File.stream!/2`, so memory usage stays roughly constant
    regardless of file size.
  * Lines are decoded through `Task.async_stream/3` with `ordered: true` and a bounded
    `:max_concurrency`, so at most `:max_concurrency` decode tasks are in flight at any
    instant and only a bounded window of results is buffered.
  * Because the stream is ordered, results are consumed in file order; the handler is
    therefore invoked exactly once per successfully decoded item, in file order.
  * Malformed lines are counted as errors and skipped; they never reach the handler and
    never abort processing or disturb the ordering of surrounding items.
  """

  @typedoc "Statistics returned by `process/3`."
  @type stats :: %{
          processed: non_neg_integer(),
          errors: non_neg_integer(),
          elapsed_ms: number(),
          throughput: float(),
          max_concurrency: pos_integer()
        }

  @doc """
  Processes the JSON array file at `file_path`, calling `handler_fn` once per successfully
  decoded item, in file order.

  ## Options

    * `:max_concurrency` - positive integer, the maximum number of lines decoded
      concurrently. Defaults to `System.schedulers_online/0`.

  Returns `{:ok, stats}` where `stats` holds `:processed`, `:errors`, `:elapsed_ms`,
  `:throughput` and `:max_concurrency`.

  ## Examples

      iex> {:ok, stats} = ParallelJsonStreamer.process("items.json", &IO.inspect/1)
      iex> stats.errors
      0

  """
  @spec process(Path.t(), (term() -> term()), keyword()) :: {:ok, stats()}
  def process(file_path, handler_fn, opts \\ [])
      when is_binary(file_path) and is_function(handler_fn, 1) and is_list(opts) do
    max_concurrency = concurrency(opts)
    started_at = System.monotonic_time(:microsecond)

    {processed, errors} =
      file_path
      |> File.stream!([], :line)
      |> Stream.map(&prepare/1)
      |> Stream.reject(&(&1 == :skip))
      |> Task.async_stream(&decode/1,
        max_concurrency: max_concurrency,
        ordered: true,
        timeout: :infinity
      )
      |> Enum.reduce({0, 0}, fn result, {ok_count, error_count} ->
        case result do
          {:ok, {:ok, item}} ->
            handler_fn.(item)
            {ok_count + 1, error_count}

          {:ok, :error} ->
            {ok_count, error_count + 1}

          {:exit, _reason} ->
            {ok_count, error_count + 1}
        end
      end)

    elapsed_ms = (System.monotonic_time(:microsecond) - started_at) / 1000

    stats = %{
      processed: processed,
      errors: errors,
      elapsed_ms: max(elapsed_ms, 0),
      throughput: throughput(processed, elapsed_ms),
      max_concurrency: max_concurrency
    }

    {:ok, stats}
  end

  @spec concurrency(keyword()) :: pos_integer()
  defp concurrency(opts) do
    case Keyword.get(opts, :max_concurrency) do
      nil -> System.schedulers_online()
      value when is_integer(value) and value > 0 -> value
      _other -> System.schedulers_online()
    end
  end

  # Trims the raw line and decides whether it carries a JSON payload. Structural lines and
  # blank lines are dropped before the concurrency window, so they never occupy a task slot.
  @spec prepare(binary()) :: {:payload, binary()} | :skip
  defp prepare(line) do
    case String.trim(line) do
      "" -> :skip
      "[" -> :skip
      "]" -> :skip
      trimmed -> {:payload, strip_trailing_comma(trimmed)}
    end
  end

  @spec strip_trailing_comma(binary()) :: binary()
  defp strip_trailing_comma(trimmed) do
    case String.ends_with?(trimmed, ",") do
      true -> binary_part(trimmed, 0, byte_size(trimmed) - 1)
      false -> trimmed
    end
  end

  @spec decode({:payload, binary()}) :: {:ok, term()} | :error
  defp decode({:payload, payload}) do
    case JSON.decode(payload) do
      {:ok, item} -> {:ok, item}
      {:error, _reason} -> :error
    end
  rescue
    _exception -> :error
  end

  @spec throughput(non_neg_integer(), number()) :: float()
  defp throughput(_processed, elapsed_ms) when elapsed_ms == 0, do: 0.0
  defp throughput(processed, elapsed_ms), do: processed / (elapsed_ms / 1000)
end