  test "drain visits in priority order and reports processed ids in that order", %{dlq: dlq} do
    {:ok, _} = PriorityDLQ.push(dlq, "q", :l1, :err, %{}, :low)
    {:ok, hid} = PriorityDLQ.push(dlq, "q", :h1, :err, %{}, :high)
    {:ok, nid} = PriorityDLQ.push(dlq, "q", :n1, :err, %{}, :normal)

    handler = fn msg ->
      Recorder.record(msg)
      :ok
    end

    assert {:ok, stats} = PriorityDLQ.drain(dlq, "q", handler, 2)

    assert Recorder.order() == [:h1, :n1]
    assert stats.succeeded == 2
    assert stats.failed == 0
    assert stats.processed == [hid, nid]

    # low priority one remains
    assert Enum.map(PriorityDLQ.peek(dlq, "q", 10), & &1.message) == [:l1]
  end