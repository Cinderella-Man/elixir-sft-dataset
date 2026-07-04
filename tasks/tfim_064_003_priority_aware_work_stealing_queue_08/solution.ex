  test "empty item list returns empty results" do
    results = WorkStealQueue.run([], 4, fn payload -> payload end)
    assert results == []
  end