  test "push ids are unique across different queues in the same server", %{dlq: dlq} do
    {:ok, a1} = DLQ.push(dlq, "a", :m1, :err, %{})
    {:ok, b1} = DLQ.push(dlq, "b", :m2, :err, %{})
    {:ok, a2} = DLQ.push(dlq, "a", :m3, :err, %{})
    {:ok, c1} = DLQ.push(dlq, "c", :m4, :err, %{})

    ids = [a1, b1, a2, c1]
    assert length(Enum.uniq(ids)) == 4

    # removing one id must leave the identically-positioned ids in other queues alone
    assert :ok = DLQ.retry(dlq, "a", a1, fn _ -> :ok end)
    assert [%{id: ^b1}] = DLQ.peek(dlq, "b", 10)
    assert [%{id: ^c1}] = DLQ.peek(dlq, "c", 10)
  end