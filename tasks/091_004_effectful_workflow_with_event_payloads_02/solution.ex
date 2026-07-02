  def transition(%{state: current} = record, event, payload) when is_map(payload) do
    case Map.fetch(@transitions, event) do
      {:ok, {^current, to}} ->
        if guard(event, record, payload) do
          updated =
            record
            |> Map.put(:state, to)
            |> effect(event, payload)

          {:ok, updated}
        else
          {:error, :guard_failed, current, event}
        end

      _ ->
        {:error, :invalid_transition, current, event}
    end
  end