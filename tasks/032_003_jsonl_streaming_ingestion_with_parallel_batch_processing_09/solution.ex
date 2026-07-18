  @spec insert_sequential(repo(), schema(), [[map()]], map(), stats()) :: stats()
  defp insert_sequential(repo, schema, batches, cfg, initial_acc) do
    Enum.reduce(batches, initial_acc, fn batch, acc ->
      do_insert_batch(repo, schema, batch, cfg, acc)
    end)
  end