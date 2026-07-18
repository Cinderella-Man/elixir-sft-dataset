  defp try_insert_batch(repo, schema, batch, cfg) do
    insert_opts = [
      on_conflict: cfg.on_conflict,
      conflict_target: cfg.conflict_target
    ]

    try do
      {count, _} = repo.insert_all(schema, batch, insert_opts)
      {:ok, count}
    rescue
      error ->
        Logger.error(
          "[JsonlIngestion] Batch failed (#{length(batch)} records): " <>
            Exception.format(:error, error, __STACKTRACE__)
        )

        {:error, length(batch)}
    catch
      kind, reason ->
        Logger.error("[JsonlIngestion] Batch failed with #{kind}: #{inspect(reason)}")
        {:error, length(batch)}
    end
  end