@impl true
def handle_info({:work_done, {:nil_req, ref}, params, outcome}, state) do
  {from, nil_pending} = Map.pop(state.nil_pending, ref)
  {result, state} = finalize(state, params, outcome)
  if from, do: GenServer.reply(from, result)
  {:noreply, %{state | nil_pending: nil_pending}}
end

def handle_info({:work_done, {:key, key}, params, outcome}, state) do
  {result, state} = finalize(state, params, outcome)
  expiry = state.clock.() + state.ttl_ms
  {entry, keys} = Map.pop(state.idempotency_keys, key)

  froms =
    case entry do
      {:pending, fs} -> fs
      _ -> []
    end

  keys = Map.put(keys, key, {:completed, result, expiry})
  Enum.each(froms, fn from -> GenServer.reply(from, result) end)
  {:noreply, %{state | idempotency_keys: keys}}
end

def handle_info(:cleanup, state) do
  now = state.clock.()

  kept =
    state.idempotency_keys
    |> Enum.filter(fn
      {_k, {:completed, _r, expiry}} -> expiry > now
      {_k, {:pending, _}} -> true
    end)
    |> Map.new()

  schedule_cleanup(state.cleanup_interval_ms)
  {:noreply, %{state | idempotency_keys: kept}}
end

def handle_info(_msg, state), do: {:noreply, state}