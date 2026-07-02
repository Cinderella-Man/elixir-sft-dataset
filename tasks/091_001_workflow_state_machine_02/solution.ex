def transition(%{state: current} = record, event) do
  case Map.fetch(@transitions, event) do
    {:ok, {^current, to}} ->
      if guard(event, record) do
        {:ok, Map.put(record, :state, to)}
      else
        {:error, :guard_failed, current, event}
      end

    _ ->
      {:error, :invalid_transition, current, event}
  end
end