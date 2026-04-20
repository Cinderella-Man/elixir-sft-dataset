@impl true
def handle_call({:acquire, bucket, rate_per_sec, burst, tokens}, _from, state) do
  now = state.clock.()

  # Derived constants.
  emission_interval = 1000 / rate_per_sec
  dvt = burst * emission_interval

  # Fresh bucket starts at TAT = now (full burst immediately available).
  tat = Map.get(state.buckets, bucket, now * 1.0)

  # Advance the TAT baseline if the bucket has been idle past it —
  # without this `max`, idle time would be credited beyond `burst`.
  new_tat = max(now, tat) + tokens * emission_interval
  earliest_admit = new_tat - dvt

  if earliest_admit <= now do
    # Accept.  The remaining burst headroom, expressed in tokens, is how
    # much slack we still have between (new_tat - now) and DVT.
    slack = dvt - (new_tat - now)
    remaining = max(trunc(slack / emission_interval), 0)

    {:reply, {:ok, remaining}, %{state | buckets: Map.put(state.buckets, bucket, new_tat)}}
  else
    # Reject.  Crucially, do NOT update TAT — repeated rejects must not
    # push the admit frontier further into the future.
    retry_after = ceil_positive(earliest_admit - now)
    {:reply, {:error, :rate_exceeded, retry_after}, state}
  end
end
