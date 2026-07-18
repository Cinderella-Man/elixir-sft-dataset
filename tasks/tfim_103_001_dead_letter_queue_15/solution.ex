  test "purge returns 0 when nothing is old enough", %{dlq: dlq} do
    {:ok, _} = DLQ.push(dlq, "q", :m, :err, %{})
    Clock.advance(100)
    assert {:ok, 0} = DLQ.purge(dlq, "q", 1_000)
    assert length(DLQ.peek(dlq, "q", 10)) == 1
  end