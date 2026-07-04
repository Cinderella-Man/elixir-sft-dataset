  test "sequential stages thread and report :sequential metadata" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:add, ok_stage(&(&1 + 1)))
      |> Pipeline.stage(:double, ok_stage(&(&1 * 2)))

    assert {:ok, 10, metadata} = Pipeline.run(pipeline, 4)
    assert Enum.map(metadata, & &1.stage) == [:add, :double]
    assert Enum.all?(metadata, &(&1.type == :sequential and &1.count == 1))
  end