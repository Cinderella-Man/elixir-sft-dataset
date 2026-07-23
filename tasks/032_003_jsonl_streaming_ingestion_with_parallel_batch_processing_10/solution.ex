  @spec insert_parallel(repo(), schema(), Enumerable.t(), map(), stats()) :: stats()
  defp insert_parallel(repo, schema, batch_stream, cfg, initial_acc) do
    # `Task.async_stream` consumes the batch stream lazily with bounded
    # concurrency, so parallel mode keeps the same memory ceiling. The
    # chunk counters ride through each task; a killed (timed-out) task
    # forfeits its counters — its batch's fate is genuinely unknown.
    batch_stream
    |> Task.async_stream(
      fn
        {[], skipped, lines} -> {{:ok, 0}, skipped, lines}
        {batch, skipped, lines} -> {try_insert_batch(repo, schema, batch, cfg), skipped, lines}
      end,
      max_concurrency: cfg.max_concurrency,
      timeout: cfg.timeout,
      on_timeout: :kill_task
    )
    |> Enum.reduce(initial_acc, fn
      {:ok, {{:ok, count}, skipped, lines}}, acc ->
        new_acc = %{
          acc
          | inserted: acc.inserted + count,
            skipped: acc.skipped + skipped,
            total: acc.total + lines
        }

        Logger.info(
          "[JsonlIngestion] Batch done — inserted: #{count}. " <>
            "Running totals — #{format_stats(new_acc)}"
        )

        new_acc

      {:ok, {{:error, batch_size}, skipped, lines}}, acc ->
        %{
          acc
          | failed: acc.failed + batch_size,
            skipped: acc.skipped + skipped,
            total: acc.total + lines
        }

      {:exit, :timeout}, acc ->
        Logger.error("[JsonlIngestion] Batch timed out")
        acc
    end)
  end