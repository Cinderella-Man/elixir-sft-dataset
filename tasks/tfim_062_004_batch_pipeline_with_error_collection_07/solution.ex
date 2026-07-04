  test "empty inputs list yields zero executions per stage" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:a, ok_stage(& &1))
      |> Pipeline.stage(:b, ok_stage(& &1))

    assert {:ok, report} = Pipeline.run(pipeline, [])
    assert report.successes == []
    assert report.failures == []
    assert Enum.map(report.stage_stats, & &1.stage) == [:a, :b]
    assert Enum.all?(report.stage_stats, &(&1.executions == 0))
    assert Enum.all?(report.stage_stats, &(&1.total_duration_us == 0))
  end