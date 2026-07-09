  defp do_attempt(
         func,
         clock_fn,
         random_fn,
         started_at,
         base_delay,
         budget,
         max_delay,
         prev_delay,
         attempts
       ) do
    attempts = attempts + 1

    case func.() do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        now = clock_fn.()
        elapsed = now - started_at

        jitter_max = prev_delay * 3
        next_delay = random_fn.(base_delay, jitter_max)
        capped_delay = min(next_delay, max_delay)

        if elapsed + capped_delay > budget do
          {:error, :budget_exhausted, reason, attempts}
        else
          target_time = now + capped_delay
          await_clock(target_time, clock_fn)

          do_attempt(
            func,
            clock_fn,
            random_fn,
            started_at,
            base_delay,
            budget,
            max_delay,
            capped_delay,
            attempts
          )
        end
    end
  end