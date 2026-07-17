  test "duplicate stage names keep per-entry execution counts independent" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:same, ok_stage(&(&1 + 1)))
      |> Pipeline.stage(:same, ok_stage(&(&1 * 2)))

    assert {:ok, report} = Pipeline.run(pipeline, [1])

    assert report.successes == [%{index: 0, result: 4}]
    assert Enum.map(report.stage_stats, & &1.stage) == [:same, :same]
    assert Enum.map(report.stage_stats, & &1.executions) == [1, 1]
  end