  test "retriable step retries until it succeeds and merges its result" do
    Process.put(:attempts, 0)

    result =
      Saga.new()
      |> Saga.step(:reserve, fn _ -> {:ok, :r} end, fn _ -> :undo end)
      |> Saga.retriable(
        :commit,
        fn _ ->
          n = Process.get(:attempts) + 1
          Process.put(:attempts, n)
          if n < 3, do: {:error, :flaky}, else: {:ok, :committed}
        end,
        5
      )
      |> Saga.execute(%{})

    assert {:ok, ctx} = result
    assert ctx.commit == :committed
    assert Process.get(:attempts) == 3
  end