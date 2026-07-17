defp flush(%{count: 0} = state), do: state

defp flush(state) do
  batch = Enum.reverse(state.buffer)
  state.on_flush.(batch)

  state
  |> Map.merge(%{buffer: [], count: 0})
  |> start_timer()
end