  defp retry_loop(func, opts, clock_fn, random_fn) do
    started_at = clock_fn.()
    base_delay = Keyword.get(opts, :base_delay_ms, 100)
    budget = Keyword.get(opts, :budget_ms, 30_000)
    max_delay = Keyword.get(opts, :max_delay_ms, 10_000)

    do_attempt(func, clock_fn, random_fn, started_at, base_delay, budget, max_delay, base_delay, 0)
  end