  test "worker_ids are within bounds" do
    items = for p <- 1..30, do: {p, p}
    results = WorkStealQueue.run(items, 5, fn payload -> payload end)

    for %{worker_id: wid} <- results do
      assert wid >= 0 and wid < 5
    end
  end