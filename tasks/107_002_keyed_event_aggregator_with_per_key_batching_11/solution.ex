  # Start a key's interval timer only on the transition from empty to non-empty.
  defp ensure_timer(%{timer: nil} = entry, key, interval_ms) do
    ref = make_ref()
    timer = Process.send_after(self(), {:flush, key, ref}, interval_ms)
    %{entry | timer: timer, timer_ref: ref}
  end

  defp ensure_timer(entry, _key, _interval_ms), do: entry