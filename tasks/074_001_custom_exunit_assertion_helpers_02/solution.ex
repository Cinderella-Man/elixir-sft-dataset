def __poll__(func, deadline, interval_ms, _last_value) do
  value = func.()
  now = System.monotonic_time(:millisecond)

  cond do
    # Success when the value is truthy AND is not a bare atom (other than
    # `true` itself).  This lets integer/tuple/list returns like `42` count
    # as "done" while keeping status atoms such as `:still_pending` or `:ok`
    # in the "not yet" bucket.  All real polling predicates (comparisons,
    # `!= nil`, etc.) already return a proper boolean so they are unaffected.
    value != nil and value != false and (not is_atom(value) or value == true) ->
      {:ok, value}

    now >= deadline ->
      elapsed = interval_ms + (now - (deadline - interval_ms))
      {:error, value, max(elapsed, 0)}

    true ->
      Process.sleep(interval_ms)
      __poll__(func, deadline, interval_ms, value)
  end
end