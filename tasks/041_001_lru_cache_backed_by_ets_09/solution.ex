  # Increment the monotonic counter and return {new_timestamp, new_state}.
  @spec next_counter(state()) :: {timestamp(), state()}
  defp next_counter(%{counter: c} = state) do
    {c + 1, %{state | counter: c + 1}}
  end