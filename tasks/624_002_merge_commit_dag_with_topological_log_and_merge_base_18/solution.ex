  defp do_merge_base(objects, a, b) do
    cond do
      not Map.has_key?(objects, a) ->
        {:error, :not_found}

      not Map.has_key?(objects, b) ->
        {:error, :not_found}

      true ->
        common = MapSet.intersection(ancestors(objects, a), ancestors(objects, b))

        case objects |> lowest_common(common) |> MapSet.to_list() |> Enum.sort() do
          [] -> {:error, :no_merge_base}
          [base | _] -> {:ok, base}
        end
    end
  end