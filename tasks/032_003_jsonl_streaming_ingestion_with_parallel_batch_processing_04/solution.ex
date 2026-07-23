  @spec stream_and_process(repo(), schema(), String.t(), map()) :: stats()
  defp stream_and_process(repo, schema, file_path, cfg) do
    schema_keys = schema_field_set(schema)
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    batch_size = cfg.batch_size

    # ONE lazy pass: lines are parsed as they are read and chunked into
    # batches that CARRY their own counters ({rows, skipped, lines}), so at
    # no point does more than a batch (plus the in-flight ones) of prepared
    # rows exist — the streaming contract the prompt and moduledoc promise.
    # Skipped lines accumulate into whichever chunk is open; the trailing
    # partial chunk is emitted at EOF even when it holds only skips, so the
    # counters always survive to the final stats.
    batch_stream =
      file_path
      |> File.stream!()
      |> Stream.map(&String.trim/1)
      |> Stream.reject(&(&1 == ""))
      |> Stream.map(fn line ->
        case parse_line(line) do
          {:ok, record} -> {:rec, prepare_row(record, schema_keys, now)}
          :skip -> :skip
        end
      end)
      |> Stream.chunk_while(
        {[], 0, 0, 0},
        fn
          {:rec, row}, {rows, nrows, skipped, lines} when nrows + 1 == batch_size ->
            {:cont, {Enum.reverse([row | rows]), skipped, lines + 1}, {[], 0, 0, 0}}

          {:rec, row}, {rows, nrows, skipped, lines} ->
            {:cont, {[row | rows], nrows + 1, skipped, lines + 1}}

          :skip, {rows, nrows, skipped, lines} ->
            {:cont, {rows, nrows, skipped + 1, lines + 1}}
        end,
        fn
          {_rows, 0, 0, 0} -> {:cont, {[], 0, 0, 0}}
          {rows, _nrows, skipped, lines} -> {:cont, {Enum.reverse(rows), skipped, lines}, nil}
        end
      )

    initial_acc = %{total: 0, inserted: 0, skipped: 0, failed: 0}

    stats =
      if cfg.max_concurrency > 1 do
        insert_parallel(repo, schema, batch_stream, cfg, initial_acc)
      else
        insert_sequential(repo, schema, batch_stream, cfg, initial_acc)
      end

    Logger.info("[JsonlIngestion] Finished. Final stats: #{format_stats(stats)}")
    stats
  end