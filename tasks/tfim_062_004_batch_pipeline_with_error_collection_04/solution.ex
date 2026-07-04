  test "all items succeed and thread through stages" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:inc, ok_stage(&(&1 + 1)))
      |> Pipeline.stage(:double, ok_stage(&(&1 * 2)))

    assert {:ok, report} = Pipeline.run(pipeline, [1, 2, 3])

    assert report.successes == [
             %{index: 0, result: 4},
             %{index: 1, result: 6},
             %{index: 2, result: 8}
           ]

    assert report.failures == []
    assert Enum.map(report.stage_stats, & &1.stage) == [:inc, :double]
    assert Enum.all?(report.stage_stats, &(&1.executions == 3))
  end