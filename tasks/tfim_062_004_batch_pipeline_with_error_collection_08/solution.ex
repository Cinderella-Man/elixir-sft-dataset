  test "stage_stats are ordered by pipeline stage order" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:alpha, ok_stage(& &1))
      |> Pipeline.stage(:beta, ok_stage(& &1))
      |> Pipeline.stage(:gamma, ok_stage(& &1))

    assert {:ok, report} = Pipeline.run(pipeline, [:x])
    assert Enum.map(report.stage_stats, & &1.stage) == [:alpha, :beta, :gamma]
  end