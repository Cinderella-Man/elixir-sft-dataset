  defp fetch_key(map, key) do
    atom_key = safe_existing_atom(key)

    cond do
      Map.has_key?(map, key) ->
        {:ok, key, Map.fetch!(map, key)}

      atom_key != nil and Map.has_key?(map, atom_key) ->
        {:ok, atom_key, Map.fetch!(map, atom_key)}

      true ->
        :error
    end
  end