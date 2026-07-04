  test "three stages thread results in order" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:add_one, ok_stage(&(&1 + 1)))
      |> Pipeline.stage(:double, ok_stage(&(&1 * 2)))
      |> Pipeline.stage(:to_string, ok_stage(&Integer.to_string/1))

    assert {:ok, "10", metadata} = Pipeline.run(pipeline, 4)
    assert Enum.map(metadata, & &1.stage) == [:add_one, :double, :to_string]
    assert Enum.all?(metadata, &(&1.attempts == 1))
  end