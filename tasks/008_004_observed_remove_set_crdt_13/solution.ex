  def handle_call({:remove, element}, _from, state) do
    # `entries` never holds an empty tag set: add always inserts a tag,
    # remove deletes the whole key, and merge drops empty survivors — so a
    # fetched entry is removable as-is.
    case Map.fetch(state.entries, element) do
      {:ok, tags} ->
        # Move all current tags to tombstones
        new_tombstones = MapSet.union(state.tombstones, tags)
        new_entries = Map.delete(state.entries, element)
        {:reply, :ok, %{state | entries: new_entries, tombstones: new_tombstones}}

      :error ->
        {:reply, {:error, :not_a_member}, state}
    end
  end
