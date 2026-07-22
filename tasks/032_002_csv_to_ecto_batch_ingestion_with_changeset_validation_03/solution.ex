  @spec process_batch(repo(), schema(), [map()], map(), stats()) :: stats()
  defp process_batch(repo, schema, batch, cfg, acc) do
    # Ecto forbids `:conflict_target` together with `on_conflict: :raise` (the
    # default), so only attach a conflict target for the conflict-handling modes.
    # With `:raise`, a duplicate key surfaces as a normal constraint error (caught
    # below and counted against this batch).
    insert_opts =
      case {cfg.on_conflict, cfg.conflict_target} do
        {:raise, _} ->
          [on_conflict: :raise]

        # An empty conflict target cannot be handed to Ecto (it rejects the
        # wrapped [:nothing]/[] as an unknown column) — omit the option, so
        # a default-opts ingest actually inserts instead of failing every
        # batch inside the rescue.
        {other, []} ->
          [on_conflict: other]

        {other, target} ->
          [on_conflict: other, conflict_target: target]
      end

    batch_size = length(batch)

    try do
      {count, _} = repo.insert_all(schema, batch, insert_opts)

      new_acc = %{acc | inserted: acc.inserted + count}

      Logger.info(
        "[CsvIngestion] Batch done — " <>
          "size: #{batch_size}, inserted: #{count}. " <>
          "Running totals — #{format_stats(new_acc)}"
      )

      new_acc
    rescue
      error ->
        Logger.error(
          "[CsvIngestion] Batch failed (#{batch_size} records skipped): " <>
            Exception.format(:error, error, __STACKTRACE__)
        )

        %{acc | failed: acc.failed + batch_size}
    catch
      kind, reason ->
        Logger.error(
          "[CsvIngestion] Batch failed with #{kind} " <>
            "(#{batch_size} records skipped): #{inspect(reason)}"
        )

        %{acc | failed: acc.failed + batch_size}
    end
  end