defp flush(%{buffer: []} = state), do: state

defp flush(state) do
  batch = Enum.reverse(state.buffer)
  state.on_flush.(batch)

  state
  |> clear_timer()
  |> Map.merge(%{buffer: [], weight: 0})
end