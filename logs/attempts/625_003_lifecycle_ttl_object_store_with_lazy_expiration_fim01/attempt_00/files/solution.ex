  def handle_call(:purge_expired, _from, state) do
    now = now_ms()

    {buckets, removed} =
      Enum.reduce(state.buckets, {%{}, 0}, fn {name, objects}, {acc, count} ->
        live = Enum.reject(objects, fn {_key, obj} -> expired?(obj, now) end)
        removed = map_size(objects) - length(live)
        {Map.put(acc, name, Map.new(live)), count + removed}
      end)

    {:reply, {:ok, removed}, %{state | buckets: buckets}}
  end