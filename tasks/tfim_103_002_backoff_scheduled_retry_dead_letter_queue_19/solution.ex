  test "retrying a dead message never invokes the handler", %{dlq: dlq} do
    {:ok, id} = BackoffDLQ.push(dlq, "q", :m, :orig, %{})
    fail = fn _ -> {:error, :again} end

    assert {:error, :again} = BackoffDLQ.retry(dlq, "q", id, fail)
    Clock.advance(1000)
    assert {:error, :again} = BackoffDLQ.retry(dlq, "q", id, fail)
    Clock.advance(2000)
    assert {:error, :again} = BackoffDLQ.retry(dlq, "q", id, fail)
    assert [dead] = BackoffDLQ.peek(dlq, "q", 10)
    assert dead.status == :dead

    parent = self()
    spy = fn _ -> send(parent, :handler_ran) end

    assert {:error, :dead} = BackoffDLQ.retry(dlq, "q", id, spy)
    refute_receive :handler_ran, 50

    # the dead entry is untouched: no removal, no extra retry counted
    assert [still] = BackoffDLQ.peek(dlq, "q", 10)
    assert still.id == id
    assert still.retry_count == 3
    assert still.status == :dead
  end