defp flush(%{count: 0} = state), do: state

defp flush(state) do
  batch = Enum.reverse(state.buffer)
  state.on_flush.(batch)

  state
  |> clear_timer()
  |> Map.merge(%{buffer: [], count: 0})
end