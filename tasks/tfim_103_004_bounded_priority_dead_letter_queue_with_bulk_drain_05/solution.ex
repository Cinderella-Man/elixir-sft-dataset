  test "peek respects count in priority order", %{dlq: dlq} do
    {:ok, _} = PriorityDLQ.push(dlq, "q", :l1, :err, %{}, :low)
    {:ok, _} = PriorityDLQ.push(dlq, "q", :h1, :err, %{}, :high)
    assert Enum.map(PriorityDLQ.peek(dlq, "q", 1), & &1.message) == [:h1]
  end