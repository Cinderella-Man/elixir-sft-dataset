  @impl true
  def handle_call({:mask, data}, _from, state) do
    {result, {ks, pa}} = walk(state, data, {0, 0})

    new_state =
      state
      |> Map.update!(:keys_masked, &(&1 + ks))
      |> Map.update!(:patterns_applied, &(&1 + pa))

    {:reply, result, new_state}
  end

  def handle_call({:mask_string, string}, _from, state) do
    {scrubbed, count} = scrub(state, string)
    new_state = Map.update!(state, :patterns_applied, &(&1 + count))
    {:reply, scrubbed, new_state}
  end

  def handle_call({:add_pattern, regex, replacement}, _from, state) do
    new_state = Map.update!(state, :patterns, &(&1 ++ [{regex, replacement}]))
    {:reply, :ok, new_state}
  end

  def handle_call(:stats, _from, state) do
    stats = %{keys_masked: state.keys_masked, patterns_applied: state.patterns_applied}
    {:reply, stats, state}
  end