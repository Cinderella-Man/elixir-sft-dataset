  test "different queues are completely independent", %{dlq: dlq} do
    {:ok, a_id} = DLQ.push(dlq, "a", :ma, :err, %{})
    {:ok, _b_id} = DLQ.push(dlq, "b", :mb, :err, %{})

    # failing retry on "a" must not touch "b"
    assert {:error, :x} = DLQ.retry(dlq, "a", a_id, fn _ -> {:error, :x} end)

    assert [ea] = DLQ.peek(dlq, "a", 10)
    assert ea.retry_count == 1

    assert [eb] = DLQ.peek(dlq, "b", 10)
    assert eb.retry_count == 0
    assert eb.message == :mb
  end