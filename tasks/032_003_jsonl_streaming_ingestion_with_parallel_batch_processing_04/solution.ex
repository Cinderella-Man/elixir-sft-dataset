  @spec stream_and_process(repo(), schema(), String.t(), map()) :: stats()
  defp stream_and_process(repo, schema, file_path, cfg) do
    schema_keys = schema_field_set(schema)
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    # Phase 1: Stream, parse, classify each line.
    {parsed_records, skipped_count, total_count} =
      file_path
      |> File.stream!()
      |> Stream.map(&String.trim/1)
      |> Stream.reject(&(&1 == ""))
      |> Enum.reduce({[], 0, 0}, fn line, {records, skipped, total} ->
        case parse_line(line) do
          {:ok, record} ->
            prepared = prepare_row(record, schema_keys, now)
            {[prepared | records], skipped, total + 1}

          :skip ->
            {records, skipped + 1, total + 1}
        end
      end)

    parsed_records = Enum.reverse(parsed_records)

    # Phase 2: Chunk into batches and insert.
    batches = Enum.chunk_every(parsed_records, cfg.batch_size)

    initial_acc = %{total: total_count, inserted: 0, skipped: skipped_count, failed: 0}

    stats =
      if cfg.max_concurrency > 1 do
        insert_parallel(repo, schema, batches, cfg, initial_acc)
      else
        insert_sequential(repo, schema, batches, cfg, initial_acc)
      end

    Logger.info("[JsonlIngestion] Finished. Final stats: #{format_stats(stats)}")
    stats
  end