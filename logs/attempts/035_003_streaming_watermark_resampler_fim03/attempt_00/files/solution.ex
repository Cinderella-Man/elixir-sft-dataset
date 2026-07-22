  defp finalize(%{next_emit: nil} = state), do: state

  defp finalize(state) do
    if state.next_emit + state.interval + state.lateness <= state.watermark do
      state
      |> close_bucket(state.next_emit)
      |> advance()
      |> finalize()
    else
      state
    end
  end