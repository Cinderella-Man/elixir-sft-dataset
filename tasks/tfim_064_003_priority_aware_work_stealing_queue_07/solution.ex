  test "worker_count greater than item count still processes everything" do
    items = [{1, :a}, {2, :b}, {3, :c}]
    results = WorkStealQueue.run(items, 10, fn payload -> payload end)

    assert length(results) == 3
    assert Enum.sort(payloads(results)) == [:a, :b, :c]
  end