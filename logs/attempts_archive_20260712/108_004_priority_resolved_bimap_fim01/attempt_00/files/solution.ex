  def handle_call({:put, key, value, priority}, _from, state) do
    %{forward: f, reverse: r, prio: p} = state

    # The pair currently sitting at `key`, if it binds a *different* value.
    key_conflict =
      case Map.fetch(f, key) do
        {:ok, ^value} -> nil
        {:ok, oldv} -> {key, oldv, Map.fetch!(p, key)}
        :error -> nil
      end

    # The pair currently sitting at `value`, if it binds a *different* key.
    value_conflict =
      case Map.fetch(r, value) do
        {:ok, ^key} -> nil
        {:ok, oldk} -> {oldk, value, Map.fetch!(p, oldk)}
        :error -> nil
      end

    conflicts = Enum.reject([key_conflict, value_conflict], &is_nil/1)

    cond do
      conflicts == [] ->
        # Same pair (priority update) or a fully free slot: install.
        {:reply, {:ok, []}, install(state, key, value, priority)}

      priority > Enum.max(Enum.map(conflicts, fn {_k, _v, cp} -> cp end)) ->
        state = Enum.reduce(conflicts, state, fn {ck, cv, _cp}, acc -> evict(acc, ck, cv) end)
        evicted = Enum.map(conflicts, fn {ck, cv, _cp} -> {ck, cv} end)
        {:reply, {:ok, evicted}, install(state, key, value, priority)}

      true ->
        {:reply, {:error, :rejected}, state}
    end
  end