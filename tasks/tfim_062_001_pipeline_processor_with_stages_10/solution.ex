  test "last stage failing returns error tuple" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:a, ok_stage(& &1))
      |> Pipeline.stage(:b, ok_stage(& &1))
      |> Pipeline.stage(:c, fail_stage(:disk_full))

    assert {:error, :c, :disk_full} = Pipeline.run(pipeline, 0)
  end