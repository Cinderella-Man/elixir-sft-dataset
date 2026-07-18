  test "concurrent consumption of the same code yields exactly one :ok", %{vault: v} do
    {:ok, _} = TOTPVault.register(v, "alice")
    t = 90_000
    {:ok, code} = TOTPVault.current_code(v, "alice", time: t)

    results =
      1..25
      |> Task.async_stream(fn _ -> TOTPVault.consume(v, "alice", code, time: t) end,
        max_concurrency: 25
      )
      |> Enum.map(fn {:ok, r} -> r end)

    assert Enum.count(results, &(&1 == :ok)) == 1
    assert Enum.count(results, &(&1 == {:error, :replayed})) == 24
  end