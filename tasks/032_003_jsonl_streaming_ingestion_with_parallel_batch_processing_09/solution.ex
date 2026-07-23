  @spec insert_sequential(repo(), schema(), Enumerable.t(), map(), stats()) :: stats()
  defp insert_sequential(repo, schema, batch_stream, cfg, initial_acc) do
    Enum.reduce(batch_stream, initial_acc, fn {rows, skipped, lines}, acc ->
      acc = %{acc | total: acc.total + lines, skipped: acc.skipped + skipped}

      case rows do
        [] -> acc
        batch -> do_insert_batch(repo, schema, batch, cfg, acc)
      end
    end)
  end