  test "new entry ids are unique across queues on the same server", %{dlq: dlq} do
    {:ok, :new, id_a} = DedupDLQ.push(dlq, "a", "k", :ma, :err, %{})
    {:ok, :new, id_b} = DedupDLQ.push(dlq, "b", "k", :mb, :err, %{})
    {:ok, :new, id_c} = DedupDLQ.push(dlq, "a", "k2", :mc, :err, %{})
    assert length(Enum.uniq([id_a, id_b, id_c])) == 3

    # an id is not recycled after its entry leaves the queue
    assert :ok = DedupDLQ.retry(dlq, "a", "k2", fn _ -> :ok end)
    {:ok, :new, id_d} = DedupDLQ.push(dlq, "a", "k3", :md, :err, %{})
    refute id_d in [id_a, id_b, id_c]
  end