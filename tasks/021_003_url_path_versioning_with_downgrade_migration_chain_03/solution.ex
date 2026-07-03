  defp steps_to(target) do
    idx = Enum.find_index(@chain, &(&1 == target))

    @chain
    |> Enum.take(idx + 1)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [from, to] -> {from, to} end)
  end