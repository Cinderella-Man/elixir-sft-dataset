# For each tier: count the in-window timestamps.  If any tier is at its
# limit, collect its retry_after and pick the tightest (longest wait).
# Otherwise, build the remaining_by_tier map.
defp evaluate_tiers(tiers, active, now) do
  results =
    Enum.map(tiers, fn {name, max_requests, window_ms} ->
      window_start = now - window_ms
      in_window = Enum.take_while(active, fn ts -> ts > window_start end)
      count = length(in_window)

      if count < max_requests do
        # `count` already-recorded requests; after accepting the new one,
        # `count + 1` will exist, leaving `max_requests - count - 1` headroom.
        {:pass, name, max_requests - count - 1}
      else
        # Tier saturated.  The oldest in-window timestamp is the last one
        # in the truncated list (timestamps are newest-first).  Wait until
        # it exits the window.
        oldest = List.last(in_window)
        retry_after = max(oldest + window_ms - now, 1)
        {:fail, name, retry_after}
      end
    end)

  case Enum.filter(results, &match?({:fail, _, _}, &1)) do
    [] ->
      remaining =
        Enum.reduce(results, %{}, fn {:pass, name, r}, acc -> Map.put(acc, name, r) end)

      {:ok, remaining}

    failures ->
      # Tightest = longest retry_after (the one the caller actually has to wait on).
      {:fail, name, retry_after} =
        Enum.max_by(failures, fn {:fail, _n, retry} -> retry end)

      {:rejected, name, retry_after}
  end
end
