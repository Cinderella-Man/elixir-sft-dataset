  test "process_fn is applied exactly once per item even when work is stolen" do
    parent = self()
    items = Enum.to_list(1..30)

    results =
      WorkStealQueue.run(items, 4, fn x ->
        send(parent, {:applied, x})
        x
      end)

    assert length(results) == 30

    seen =
      for _ <- 1..30 do
        assert_receive {:applied, x}, 1_000
        x
      end

    assert Enum.sort(seen) == items
    refute_receive {:applied, _}, 100
  end