  test "empty pipeline reports every item as an identity success" do
    assert {:ok, report} = Pipeline.run(Pipeline.new(), [1, 2, 3])

    assert report.successes == [
             %{index: 0, result: 1},
             %{index: 1, result: 2},
             %{index: 2, result: 3}
           ]

    assert report.failures == []
    assert report.stage_stats == []
  end