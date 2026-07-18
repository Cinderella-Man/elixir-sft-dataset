  @impl true
  def handle_call({:add, item}, _from, state) do
    id = Map.fetch!(item, :id)

    if MapSet.member?(state.ids, id) do
      {:reply, {:error, {:duplicate_id, id}}, state}
    else
      {:reply, :ok, put_item(state, item, id)}
    end
  end

  def handle_call({:add_many, items}, _from, state) do
    new_state =
      Enum.reduce(items, state, fn item, acc ->
        id = Map.fetch!(item, :id)

        if MapSet.member?(acc.ids, id) do
          acc
        else
          put_item(acc, item, id)
        end
      end)

    {:reply, :ok, new_state}
  end

  def handle_call(:forest, _from, state) do
    ordered = Enum.reverse(state.items)
    {:reply, do_build(ordered, state.strategy), state}
  end

  def handle_call(:count, _from, state) do
    {:reply, MapSet.size(state.ids), state}
  end