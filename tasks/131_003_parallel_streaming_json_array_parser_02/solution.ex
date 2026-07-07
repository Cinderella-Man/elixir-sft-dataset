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
