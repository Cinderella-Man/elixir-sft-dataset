  def process(file_path, handler_fn) when is_function(handler_fn, 1) do
    start = System.monotonic_time(:microsecond)

    {processed, errors} =
      file_path
      |> File.stream!([], :line)
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