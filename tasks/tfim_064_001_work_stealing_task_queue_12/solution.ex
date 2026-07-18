  test "no duplicate processing — each item processed exactly once" do
    items = Enum.to_list(1..40)
    results = WorkStealQueue.run(items, 4, fn x -> x end)

    assert length(results) == 40
    assert length(Enum.uniq_by(results, & &1.item)) == 40
  end