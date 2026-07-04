  test "an item failing at the first stage records that stage" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:first, fn _ -> {:error, :nope} end)
      |> Pipeline.stage(:second, ok_stage(& &1))

    assert {:ok, report} = Pipeline.run(pipeline, [42])
    assert report.successes == []
    assert report.failures == [%{index: 0, stage: :first, reason: :nope}]

    stats = Map.new(report.stage_stats, fn s -> {s.stage, s.executions} end)
    assert stats == %{first: 1, second: 0}
  end