  test "peek orders by priority then FIFO within a priority", %{dlq: dlq} do
    {:ok, _} = PriorityDLQ.push(dlq, "q", :l1, :err, %{}, :low)
    {:ok, _} = PriorityDLQ.push(dlq, "q", :h1, :err, %{}, :high)
    {:ok, _} = PriorityDLQ.push(dlq, "q", :n1, :err, %{}, :normal)
    {:ok, _} = PriorityDLQ.push(dlq, "q", :h2, :err, %{}, :high)
    {:ok, _} = PriorityDLQ.push(dlq, "q", :l2, :err, %{}, :low)

    assert Enum.map(PriorityDLQ.peek(dlq, "q", 10), & &1.message) ==
             [:h1, :h2, :n1, :l1, :l2]
  end