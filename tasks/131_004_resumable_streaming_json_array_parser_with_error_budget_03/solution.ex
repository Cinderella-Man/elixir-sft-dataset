  def process(file_path, handler_fn, opts \\ []) when is_function(handler_fn, 1) do
    max_errors = Keyword.get(opts, :max_errors, :infinity)
    resume_from = Keyword.get(opts, :resume_from, 0)
    start = System.monotonic_time(:microsecond)

    init = %{processed: 0, errors: 0, index: 0, aborted: false}

    result =
      file_path
      |> File.stream!([], :line)
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