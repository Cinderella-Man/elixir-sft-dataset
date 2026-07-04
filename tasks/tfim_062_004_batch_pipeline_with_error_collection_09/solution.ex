  test "total_duration_us accumulates across items" do
    slow =
      fn v ->
        Process.sleep(5)
        {:ok, v}
      end

    pipeline = Pipeline.new() |> Pipeline.stage(:slow, slow)

    assert {:ok, report} = Pipeline.run(pipeline, [1, 1])
    [%{stage: :slow, executions: 2, total_duration_us: d}] = report.stage_stats
    assert d >= 8_000
  end