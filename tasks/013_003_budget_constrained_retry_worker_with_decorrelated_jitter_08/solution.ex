  defp await_clock(target_time, clock_fn) do
    if clock_fn.() < target_time do
      receive do
      after
        0 -> await_clock(target_time, clock_fn)
      end
    end
  end