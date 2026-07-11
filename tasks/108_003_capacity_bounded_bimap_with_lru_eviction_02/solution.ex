  @impl true
  def handle_call({:put, key, value}, _from, state) do
    %{forward: f, reverse: r, access: a, clock: c, capacity: cap} = state

    key_existed = Map.has_key?(f, key)

    # Bijection maintenance step 1: if key rebinds to a new value, orphan old value.
    r =
      case Map.fetch(f, key) do
        {:ok, ^value} -> r
        {:ok, oldv} -> Map.delete(r, oldv)
        :error -> r
      end

    # Bijection maintenance step 2: if value rebinds to a new key, evict old key.
    {f, r, a} =
      case Map.fetch(r, value) do
        {:ok, ^key} -> {f, r, a}
        {:ok, oldk} -> {Map.delete(f, oldk), r, Map.delete(a, oldk)}
        :error -> {f, r, a}
      end

    # LRU eviction only when a genuinely new key would push us past capacity.
    {f, r, a} =
      if not key_existed and map_size(f) >= cap do
        evict_lru(f, r, a)
      else
        {f, r, a}
      end

    f = Map.put(f, key, value)
    r = Map.put(r, value, key)
    a = Map.put(a, key, c)

    {:reply, :ok, %{state | forward: f, reverse: r, access: a, clock: c + 1}}
  end

  def handle_call({:get_by_key, key}, _from, state) do
    case Map.fetch(state.forward, key) do
      {:ok, v} -> {:reply, {:ok, v}, touch(state, key)}
      :error -> {:reply, :error, state}
    end
  end

  def handle_call({:get_by_value, value}, _from, state) do
    case Map.fetch(state.reverse, value) do
      {:ok, k} -> {:reply, {:ok, k}, touch(state, k)}
      :error -> {:reply, :error, state}
    end
  end

  def handle_call({:delete, key}, _from, state) do
    case Map.fetch(state.forward, key) do
      {:ok, v} ->
        new_state = %{
          state
          | forward: Map.delete(state.forward, key),
            reverse: Map.delete(state.reverse, v),
            access: Map.delete(state.access, key)
        }

        {:reply, :ok, new_state}

      :error ->
        {:reply, :ok, state}
    end
  end

  def handle_call(:size, _from, state), do: {:reply, map_size(state.forward), state}

  def handle_call(:keys_by_recency, _from, state) do
    keys =
      state.access
      |> Enum.sort_by(fn {_k, tick} -> tick end)
      |> Enum.map(fn {k, _tick} -> k end)

    {:reply, keys, state}
  end