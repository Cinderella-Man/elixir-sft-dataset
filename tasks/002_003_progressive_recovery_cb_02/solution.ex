defp execute_in_closed(state, func) do
  case execute_and_classify(func) do
    {:ok, reply} ->
      # Consecutive failure run is broken — reset counter.
      {reply, %{state | failure_count: 0}}

    {:error, reply} ->
      new_count = state.failure_count + 1

      if new_count >= state.config.failure_threshold do
        {reply,
          %{state | state: :open, opened_at: state.clock.(), failure_count: 0}}
      else
        {reply, %{state | failure_count: new_count}}
      end
  end
end
