  test "retries take progressively longer", %{rd: rd} do
    {:ok, timestamps} = Agent.start_link(fn -> [] end)

    func = fn ->
      Agent.update(timestamps, fn ts -> ts ++ [System.monotonic_time(:millisecond)] end)
      {:error, :nope}
    end

    RetryDedup.execute(rd, "timing", func,
      max_retries: 3,
      base_delay_ms: 50,
      max_delay_ms: 1_000
    )

    ts = Agent.get(timestamps, & &1)
    # Should have 4 timestamps: initial + 3 retries
    assert length(ts) == 4

    delays =
      ts
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> b - a end)

    # Each delay should be roughly: 50, 100, 200 (exponential)
    # Allow some slack for scheduling
    [d1, d2, d3] = delays
    assert d1 >= 30
    assert d2 >= d1
    assert d3 >= d2
  end