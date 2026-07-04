  test "empty item list returns empty results" do
    results = WorkStealQueue.run([], 4, fn x -> x end)
    assert results == []
  end