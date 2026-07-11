  test "peek respects count and returns oldest-first order", %{dlq: dlq} do
    {:ok, _} = DLQ.push(dlq, "q", :first, :err, %{})
    Clock.advance(1)
    {:ok, _} = DLQ.push(dlq, "q", :second, :err, %{})
    Clock.advance(1)
    {:ok, _} = DLQ.push(dlq, "q", :third, :err, %{})

    two = DLQ.peek(dlq, "q", 2)
    assert length(two) == 2
    assert Enum.map(two, & &1.message) == [:first, :second]

    all = DLQ.peek(dlq, "q", 10)
    assert Enum.map(all, & &1.message) == [:first, :second, :third]
  end