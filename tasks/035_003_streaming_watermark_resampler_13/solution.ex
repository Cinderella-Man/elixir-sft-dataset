  defp do_flush(state, last_bucket) do
    if state.next_emit <= last_bucket do
      state
      |> close_bucket(state.next_emit)
      |> advance()
      |> do_flush(last_bucket)
    else
      state
    end
  end