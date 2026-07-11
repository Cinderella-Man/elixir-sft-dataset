  test "different keys are independent entries", %{dlq: dlq} do
    {:ok, :new, _} = DedupDLQ.push(dlq, "q", "a", :ma, :err, %{})
    {:ok, :new, _} = DedupDLQ.push(dlq, "q", "b", :mb, :err, %{})
    assert length(DedupDLQ.peek(dlq, "q", 10)) == 2
  end