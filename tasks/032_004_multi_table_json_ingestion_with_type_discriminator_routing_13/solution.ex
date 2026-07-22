  defp batch_info_after_failure(schema, batch_size, acc) do
    Logger.info(
      "[MultiSchemaIngestion] #{inspect(schema)} batch done (failed) — " <>
        "size: #{batch_size}, inserted: 0. " <>
        "Running totals — inserted=#{acc.inserted} failed=#{acc.failed}"
    )

    acc
  end