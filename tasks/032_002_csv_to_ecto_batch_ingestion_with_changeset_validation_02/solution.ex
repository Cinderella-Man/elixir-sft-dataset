  defp process_rows(repo, schema, {headers, data_rows}, field_mapping, cfg) do
    atom_headers = map_headers(headers, field_mapping)
    schema_keys  = schema_field_set(schema)
    now          = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    total = length(data_rows)

    # Validate each row via changeset; split into valid and invalid.
    {valid_rows, validation_errors} =
      data_rows
      |> Enum.with_index(2)   # line 2 is the first data row
      |> Enum.reduce({[], []}, fn {cells, line_num}, {valid_acc, err_acc} ->
        attrs = build_attrs(cells, atom_headers, schema_keys)
        changeset = schema.changeset(struct(schema), attrs)

        if changeset.valid? do
          row =
            changeset.changes
            |> maybe_put_ts(:inserted_at, now, schema_keys)
            |> maybe_put_ts(:updated_at,  now, schema_keys)

          {[row | valid_acc], err_acc}
        else
          {valid_acc, [{line_num, changeset.errors} | err_acc]}
        end
      end)

    valid_rows       = Enum.reverse(valid_rows)
    validation_errors = Enum.reverse(validation_errors)
    invalid_count    = length(validation_errors)

    # Batch-insert valid rows.
    initial_acc = %{total: total, inserted: 0, invalid: invalid_count,
                    failed: 0, validation_errors: validation_errors}

    stats =
      valid_rows
      |> Enum.chunk_every(cfg.batch_size)
      |> Enum.reduce(initial_acc, fn batch, acc ->
        process_batch(repo, schema, batch, cfg, acc)
      end)

    Logger.info("[CsvIngestion] Finished. Final stats: #{format_stats(stats)}")
    stats
  end