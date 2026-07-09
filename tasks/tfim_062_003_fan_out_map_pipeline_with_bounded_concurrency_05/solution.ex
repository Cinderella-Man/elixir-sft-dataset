  test "map stage processes every element and threads a list forward" do
    pipeline =
      Pipeline.new()
      |> Pipeline.map_stage(:double_each, fn x -> {:ok, x * 2} end)
      |> Pipeline.stage(:sum, ok_stage(&Enum.sum/1))

    assert {:ok, 12, metadata} = Pipeline.run(pipeline, [1, 2, 3])

    assert [%{stage: :double_each, type: :map, count: 3}, %{stage: :sum, type: :sequential}] =
             metadata
  end