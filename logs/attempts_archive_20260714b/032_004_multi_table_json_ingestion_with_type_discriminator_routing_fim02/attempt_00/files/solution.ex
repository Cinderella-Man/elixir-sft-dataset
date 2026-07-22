  defp insert_schema_group(repo, schema, records, cfg) do
    schema_keys = schema_field_set(schema)
    now         = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    conflict_target = resolve_conflict_target(cfg.conflict_target, schema)

    insert_opts = [
      on_conflict:     cfg.on_conflict,
      conflict_target: conflict_target
    ]

    initial = %{inserted: 0, failed: 0}

    records
    |> Enum.map(&prepare_row(&1, schema_keys, cfg.type_field, now))
    |> Enum.chunk_every(cfg.batch_size)
    |> Enum.reduce(initial, fn batch, acc ->
      batch_size = length(batch)

      try do
        {count, _} = repo.insert_all(schema, batch, insert_opts)

        new_acc = %{acc | inserted: acc.inserted + count}

        Logger.info("[MultiSchemaIngestion] #{inspect(schema)} batch done — " <>
          "size: #{batch_size}, inserted: #{count}. " <>
          "Running totals — inserted=#{new_acc.inserted} failed=#{new_acc.failed}")

        new_acc
      rescue
        error ->
          Logger.error("[MultiSchemaIngestion] #{inspect(schema)} batch failed " <>
            "(#{batch_size} records skipped): " <>
            Exception.format(:error, error, __STACKTRACE__))
          %{acc | failed: acc.failed + batch_size}
      catch
        kind, reason ->
          Logger.error("[MultiSchemaIngestion] #{inspect(schema)} batch failed " <>
            "with #{kind} (#{batch_size} records skipped): #{inspect(reason)}")
          %{acc | failed: acc.failed + batch_size}
      end
    end)
  end