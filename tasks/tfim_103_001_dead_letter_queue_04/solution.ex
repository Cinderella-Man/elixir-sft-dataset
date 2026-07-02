  test "push returns unique ids within the same queue", %{dlq: dlq} do
    {:ok, id1} = DLQ.push(dlq, "q", :a, :err, %{})
    {:ok, id2} = DLQ.push(dlq, "q", :b, :err, %{})
    {:ok, id3} = DLQ.push(dlq, "q", :c, :err, %{})
    assert Enum.uniq([id1, id2, id3]) == [id1, id2, id3]
  end