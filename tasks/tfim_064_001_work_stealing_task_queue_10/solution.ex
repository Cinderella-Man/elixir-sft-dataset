  test "single item is processed correctly" do
    assert [%{item: :hello, result: :world, worker_id: wid}] =
             WorkStealQueue.run([:hello], 3, fn _ -> :world end)

    assert wid >= 0 and wid < 3
  end