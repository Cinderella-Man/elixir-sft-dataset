  # Bounded-tick wait against the injected clock: sleep 1ms per check so a
  # fake-clock test advances deterministically while a real clock never pegs
  # a scheduler. The budget is deliberately NOT re-checked here — the single
  # post-attempt clock reading already decided this wait fits the budget.
  defp await_clock(target_time, clock_fn) do
    if clock_fn.() < target_time do
      receive do
      after
        1 -> await_clock(target_time, clock_fn)
      end
    end
  end