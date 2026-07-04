  test "failed revalidation leaves entry in place; next stale read retries", %{c: c} do
    # Loader that raises — but after a retry, returns a value
    start_supervised!({Loader, [:from_retry]})

    counter = :counters.new(1, [])
    :counters.put(counter, 1, 0)

    loader = fn ->
      :counters.add(counter, 1, 1)

      if :counters.get(counter, 1) == 1 do
        raise "first call always fails"
      else
        Loader.next_value()
      end
    end

    :ok = SwrCache.put(c, :a, :v1, 1_000, 2_000, loader)

    Clock.advance(1_000)
    assert {:ok, :v1, :stale} = SwrCache.get(c, :a)
    :ok = wait_for_idle(c)

    # Failed revalidation → entry unchanged (still the original :v1, still stale)
    assert {:ok, :v1, :stale} = SwrCache.get(c, :a)
    :ok = wait_for_idle(c)

    assert {:ok, :from_retry, :fresh} = SwrCache.get(c, :a)
  end