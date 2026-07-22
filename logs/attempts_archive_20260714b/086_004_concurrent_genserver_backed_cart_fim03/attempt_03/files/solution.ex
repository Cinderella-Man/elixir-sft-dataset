  @impl true
  def handle_call({:add_item, product_id, quantity, unit_price}, _from, state)
      when is_integer(quantity) and quantity > 0 do
    items =
      Map.update(
        state.items,
        product_id,
        %{product_id: product_id, quantity: quantity, unit_price: unit_price},
        fn existing -> Map.put(existing, :quantity, existing.quantity + quantity) end
      )

    {:reply, :ok, %{state | items: items}}
  end

  def handle_call({:add_item, _product_id, _quantity, _unit_price}, _from, state) do
    {:reply, {:error, :invalid_quantity}, state}
  end

  def handle_call({:remove_item, product_id}, _from, state) do
    {:reply, :ok, %{state | items: Map.delete(state.items, product_id)}}
  end

  def handle_call({:update_quantity, product_id, quantity}, _from, state)
      when is_integer(quantity) and quantity >= 0 do
    case Map.fetch(state.items, product_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, _item} when quantity == 0 ->
        {:reply, :ok, %{state | items: Map.delete(state.items, product_id)}}

      {:ok, item} ->
        updated = Map.put(state.items, product_id, Map.put(item, :quantity, quantity))
        {:reply, :ok, %{state | items: updated}}
    end
  end

  def handle_call({:update_quantity, _product_id, _quantity}, _from, state) do
    {:reply, {:error, :invalid_quantity}, state}
  end

  def handle_call(:totals, _from, state) do
    {:reply, compute_totals(state), state}
  end