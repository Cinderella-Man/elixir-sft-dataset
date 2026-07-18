  test "ready returns at most count due entries, oldest-first, skipping not-yet-due ones", %{
    dlq: dlq
  } do
    {:ok, a} = BackoffDLQ.push(dlq, "q", :first, :err, %{})
    Clock.advance(10)
    {:ok, b} = BackoffDLQ.push(dlq, "q", :second, :err, %{})
    Clock.advance(10)
    {:ok, c} = BackoffDLQ.push(dlq, "q", :third, :err, %{})

    # all three are immediately due: count caps the result, oldest-first
    assert Enum.map(BackoffDLQ.ready(dlq, "q", 10), & &1.id) == [a, b, c]
    assert [r1, r2] = BackoffDLQ.ready(dlq, "q", 2)
    assert r1.id == a
    assert r2.id == b

    # failing the oldest pushes it past its backoff, so the next two due entries fill the count
    assert {:error, :boom} = BackoffDLQ.retry(dlq, "q", a, fn _ -> {:error, :boom} end)
    assert Enum.map(BackoffDLQ.ready(dlq, "q", 2), & &1.id) == [b, c]
  end