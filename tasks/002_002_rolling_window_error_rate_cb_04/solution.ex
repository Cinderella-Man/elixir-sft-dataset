defp execute_in_closed(state, func) do
  {outcome, reply} = execute_and_classify(func)

  outcomes =
    [outcome | state.outcomes]
    |> Enum.take(state.config.window_size)

  if should_trip?(outcomes, state.config) do
    {reply,
      %{state | state: :open, opened_at: state.clock.(), outcomes: [], probes_in_flight: 0}}
  else
    {reply, %{state | outcomes: outcomes}}
  end
end
