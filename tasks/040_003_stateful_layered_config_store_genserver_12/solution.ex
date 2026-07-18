  @impl true
  def handle_call({:put_layer, name, map}, _from, state) do
    layers =
      if List.keymember?(state.layers, name, 0) do
        List.keyreplace(state.layers, name, 0, {name, map})
      else
        state.layers ++ [{name, map}]
      end

    {:reply, :ok, %{state | layers: layers}}
  end

  def handle_call({:drop_layer, name}, _from, state) do
    {:reply, :ok, %{state | layers: List.keydelete(state.layers, name, 0)}}
  end

  def handle_call(:layers, _from, state) do
    {:reply, Enum.map(state.layers, fn {name, _map} -> name end), state}
  end

  def handle_call(:get_config, _from, state) do
    {:reply, compute(state), state}
  end

  def handle_call({:get, key_path}, _from, state) do
    {:reply, fetch_path(compute(state), key_path), state}
  end