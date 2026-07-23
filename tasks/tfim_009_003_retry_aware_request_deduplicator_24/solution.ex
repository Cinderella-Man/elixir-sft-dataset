  test "cap binds only once the exponential term outgrows it", %{rd: rd} do
    {:ok, timestamps} = Agent.start_link(fn -> [] end)

    func = fn ->
      Agent.update(timestamps, fn ts -> ts ++ [System.monotonic_time(:millisecond)] end)
      {:error, :nope}
    end

    assert {:error, :nope} =
             RetryDedup.execute(rd, "cap_binds", func,
               max_retries: 5,
               base_delay_ms: 40,
               max_delay_ms: 60
             )

    ts = Agent.get(timestamps, & &1)
    # initial + 5 retries = 6 invocations
    assert length(ts) == 6

    first = hd(ts)
    last = List.last(ts)

    [d1 | _] =
      ts
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> b - a end)

    # The first retry waits min(40 * 2^0, 60) == 40 ms — the cap is not yet
    # binding, so the base delay must still be honoured.
    assert d1 >= 25

    # From the second retry on, min(40 * 2^n, 60) == 60: the five gaps sum to
    # about 280 ms. Ignoring the cap would grow them 40, 80, 160, 320, 640 ms,
    # for well over a second in total.
    assert last - first < 700
  end