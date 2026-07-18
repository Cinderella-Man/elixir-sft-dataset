  test "purge can clear the whole queue and counts everything removed", %{dlq: dlq} do
    {:ok, _} = DLQ.push(dlq, "q", :m1, :err, %{})
    {:ok, _} = DLQ.push(dlq, "q", :m2, :err, %{})
    {:ok, _} = DLQ.push(dlq, "q", :m3, :err, %{})

    Clock.advance(5_000)
    assert {:ok, 3} = DLQ.purge(dlq, "q", 1_000)
    assert DLQ.peek(dlq, "q", 10) == []
  end