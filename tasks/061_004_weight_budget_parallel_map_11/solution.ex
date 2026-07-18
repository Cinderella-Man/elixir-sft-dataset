  # Admit as many queued elements as the budget allows, then wait for one to
  # finish; repeat until everything is done.
  defp run(state) do
    state = admit(state)

    if map_size(state.running) == 0 and state.queue == [] do
      state.results
    else
      state |> collect_one() |> run()
    end
  end