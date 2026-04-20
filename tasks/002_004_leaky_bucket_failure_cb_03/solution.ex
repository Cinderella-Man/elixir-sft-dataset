defp execute_in_closed(state, func) do
  # Apply leak first so the bucket reflects real time before we evaluate.
  state = apply_leak(state)

  case execute_and_classify(func) do
    {:ok, reply} ->
      # Success doesn't touch the bucket.
      {reply, state}

    {:error, reply} ->
      new_level = state.bucket_level + state.config.failure_weight
      state = %{state | bucket_level: new_level}

      if new_level >= state.config.bucket_capacity do
        # Trip.  Reset bucket so the eventual probe cycle starts clean.
        {reply,
          %{state | state: :open, opened_at: state.clock.(), bucket_level: 0.0}}
      else
        {reply, state}
      end
  end
end
