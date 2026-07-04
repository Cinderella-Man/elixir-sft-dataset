  test "single item is processed correctly" do
    %{results: results} = WorkStealQueue.run([:hello], 3, fn _ -> :world end)
    assert [%{item: :hello, result: :world, worker_id: wid}] = results
    assert wid >= 0 and wid < 3
  end