  test "retry delay never exceeds :max_delay_ms", %{rd: rd} do
    {:ok, timestamps} = Agent.start_link(fn -> [] end)

    func = fn ->
      Agent.update(timestamps, fn ts -> ts ++ [System.monotonic_time(:millisecond)] end)
      {:error, :nope}
    end

    assert {:error, :nope} =
             RetryDedup.execute(rd, "capped", func,
               max_retries: 3,
               base_delay_ms: 500,
               max_delay_ms: 40
             )

    ts = Agent.get(timestamps, & &1)
    assert length(ts) == 4

    delays =
      ts
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> b - a end)

    # min(500 * 2^(attempt - 1), 40) == 40 for every retry here; without the cap
    # the gaps would be 500, 1000 and 2000 ms.
    assert Enum.all?(delays, &(&1 < 300))
  end