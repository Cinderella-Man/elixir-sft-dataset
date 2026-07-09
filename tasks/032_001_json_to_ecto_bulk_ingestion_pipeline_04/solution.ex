  @spec process_batch(repo(), schema(), list(), non_neg_integer(), map(), stats()) :: stats()
  defp process_batch(repo, schema, prepared_batch, raw_count, cfg, acc) do
    insert_opts = build_insert_opts(cfg)

    try do
      {_count, returned_rows} = repo.insert_all(schema, prepared_batch, insert_opts)
      {ins, upd} = classify_rows(returned_rows, raw_count, cfg.returning)

      new_acc = %{acc | inserted: acc.inserted + ins, updated: acc.updated + upd}

      Logger.info(
        "[DataIngestion] Batch done — " <>
          "size: #{raw_count}, inserted: #{ins}, updated: #{upd}. " <>
          "Running totals — #{format_stats(new_acc)}"
      )

      new_acc
    rescue
      error ->
        Logger.error(
          "[DataIngestion] Batch failed (#{raw_count} records skipped): " <>
            Exception.format(:error, error, __STACKTRACE__)
        )

        %{acc | failed: acc.failed + raw_count}
    catch
      kind, reason ->
        Logger.error(
          "[DataIngestion] Batch failed with #{kind} " <>
            "(#{raw_count} records skipped): #{inspect(reason)}"
        )

        %{acc | failed: acc.failed + raw_count}
    end
  end