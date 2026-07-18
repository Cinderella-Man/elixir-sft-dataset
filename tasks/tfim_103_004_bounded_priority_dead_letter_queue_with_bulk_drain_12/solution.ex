  test "peek entries expose error_reason and metadata as pushed", %{dlq: dlq} do
    {:ok, id} = PriorityDLQ.push(dlq, "q", %{n: 7}, {:timeout, 5000}, %{source: "web"}, :high)

    assert [e] = PriorityDLQ.peek(dlq, "q", 10)
    assert e.id == id
    assert e.message == %{n: 7}
    assert e.error_reason == {:timeout, 5000}
    assert e.metadata == %{source: "web"}
    assert e.priority == :high
    assert e.retry_count == 0
  end