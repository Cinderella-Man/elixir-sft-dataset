  # Drives the pool: fill idle slots, then wait for the next completion or the
  # global deadline.
  #
  #   pending - list of {name, fetch_fn} not yet started
  #   running - map of pid => {monitor_ref, name} for in-flight fetches
  #   results - map of name => result_tuple
  defp loop(pending, running, results, max, deadline) do
    {pending, running} = fill(pending, running, max)

    if pending == [] and map_size(running) == 0 do
      results
    else
      remaining = deadline - System.monotonic_time(:millisecond)

      if remaining <= 0 do
        finalize_timeout(pending, running, results)
      else
        collect(pending, running, results, max, deadline, remaining)
      end
    end
  end