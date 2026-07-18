  @spec process_batches(repo(), schema(), list(), map()) :: stats()
  defp process_batches(repo, schema, records, cfg) do
    total = length(records)
    schema_keys = schema_field_set(schema)
    initial_acc = %{total: total, inserted: 0, updated: 0, failed: 0}

    stats =
      records
      |> Enum.chunk_every(cfg.batch_size)
      |> Enum.reduce(initial_acc, fn raw_batch, acc ->
        # Prepare rows: atomise keys, drop unknown fields, inject timestamps.
        prepared = prepare_rows(raw_batch, schema_keys)
        process_batch(repo, schema, prepared, length(raw_batch), cfg, acc)
      end)

    Logger.info("[DataIngestion] Finished. Final stats: #{format_stats(stats)}")
    stats
  end