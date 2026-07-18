  @spec insert_parallel(repo(), schema(), [[map()]], map(), stats()) :: stats()
  defp insert_parallel(repo, schema, batches, cfg, initial_acc) do
    results =
      batches
      |> Task.async_stream(
        fn batch -> try_insert_batch(repo, schema, batch, cfg) end,
        max_concurrency: cfg.max_concurrency,
        timeout: cfg.timeout,
        on_timeout: :kill_task
      )
      |> Enum.to_list()

    Enum.reduce(results, initial_acc, fn
      {:ok, {:ok, count}}, acc ->
        new_acc = %{acc | inserted: acc.inserted + count}

        Logger.info(
          "[JsonlIngestion] Batch done — inserted: #{count}. " <>
            "Running totals — #{format_stats(new_acc)}"
        )

        new_acc

      {:ok, {:error, batch_size}}, acc ->
        %{acc | failed: acc.failed + batch_size}

      {:exit, :timeout}, acc ->
        Logger.error("[JsonlIngestion] Batch timed out")
        acc
    end)
  end