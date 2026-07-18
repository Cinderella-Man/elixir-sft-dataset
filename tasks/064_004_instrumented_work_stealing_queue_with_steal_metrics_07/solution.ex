  defp loop(id, coordinator, process_fn, batch, acc) do
    case pop_item(id, coordinator) do
      {:ok, item} ->
        entry = %{item: item, result: process_fn.(item), worker_id: id}
        loop(id, coordinator, process_fn, batch, %{acc | results: [entry | acc.results]})

      :empty ->
        steal_phase(id, coordinator, process_fn, batch, acc)
    end
  end