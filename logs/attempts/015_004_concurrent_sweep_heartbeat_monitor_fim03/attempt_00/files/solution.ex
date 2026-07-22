  # Apply every gathered result, then fire callbacks for actual transitions.
  @spec apply_all(map(), map()) :: map()
  defp apply_all(state, results) do
    {new_services, callbacks} =
      Enum.reduce(state.services, {%{}, []}, fn {name, svc}, {acc, cbs} ->
        result = Map.fetch!(results, name)
        {new_svc, transition?, new_status} = apply_result(svc, result)
        cbs = if transition?, do: [{svc.on_change, name, new_status} | cbs], else: cbs
        {Map.put(acc, name, new_svc), cbs}
      end)

    Enum.each(callbacks, fn {cb, name, status} -> cb.(name, status) end)
    %{state | services: new_services}
  end