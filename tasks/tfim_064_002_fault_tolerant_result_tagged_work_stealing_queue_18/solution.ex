  test "idle workers give up when the only item fails and run/3 still returns" do
    results = WorkStealQueue.run([:boom_item], 8, fn _ -> raise "kaboom" end)

    assert [%{item: :boom_item, result: result, worker_id: wid}] = results
    assert result == {:error, %{kind: :error, reason: "kaboom"}}
    assert wid >= 0 and wid < 8
  end