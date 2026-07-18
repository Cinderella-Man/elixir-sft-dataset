  test "pipeline works with list input" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:filter, ok_stage(&Enum.filter(&1, fn x -> x > 2 end)))
      |> Pipeline.stage(:sum, ok_stage(&Enum.sum/1))

    assert {:ok, 12, _} = Pipeline.run(pipeline, [1, 2, 3, 4, 5])
  end