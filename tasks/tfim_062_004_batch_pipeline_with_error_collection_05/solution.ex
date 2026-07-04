  test "a failing item is isolated; others still succeed" do
    guard = fn v -> if v == 3, do: {:error, :bad}, else: {:ok, v} end

    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:inc, ok_stage(&(&1 + 1)))
      |> Pipeline.stage(:guard, guard)
      |> Pipeline.stage(:double, ok_stage(&(&1 * 2)))

    assert {:ok, report} = Pipeline.run(pipeline, [1, 2, 3])

    # item0: 1->2->guard ok(2)->4 ; item1: 2->3->guard fails ; item2: 3->4->guard ok->8
    assert report.successes == [%{index: 0, result: 4}, %{index: 2, result: 8}]
    assert report.failures == [%{index: 1, stage: :guard, reason: :bad}]
  end