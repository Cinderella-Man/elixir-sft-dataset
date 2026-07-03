  defp do_topo(creatable, parent_of, placed, acc) do
    ready =
      creatable
      |> MapSet.to_list()
      |> Enum.reject(&MapSet.member?(placed, &1))
      |> Enum.filter(fn i ->
        case parent_of[i] do
          nil -> true
          p -> MapSet.member?(placed, p)
        end
      end)
      |> Enum.sort()

    case ready do
      [] ->
        Enum.reverse(acc)

      _ ->
        new_placed = Enum.reduce(ready, placed, &MapSet.put(&2, &1))
        do_topo(creatable, parent_of, new_placed, Enum.reverse(ready) ++ acc)
    end
  end