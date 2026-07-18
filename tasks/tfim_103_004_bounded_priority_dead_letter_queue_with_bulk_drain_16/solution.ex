  test "capacity defaults to :infinity so pushes are never rejected", %{} do
    {:ok, dlq} = PriorityDLQ.start_link(clock: &Clock.now/0)

    for n <- 1..50 do
      assert {:ok, _} = PriorityDLQ.push(dlq, "q", {:m, n}, :err, %{}, :low)
    end

    assert length(PriorityDLQ.peek(dlq, "q", 100)) == 50
  end