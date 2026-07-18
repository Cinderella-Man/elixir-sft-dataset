  test "successful metadata entries are ordered by execution" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:alpha, ok_stage(& &1))
      |> Pipeline.stage(:beta, ok_stage(& &1))
      |> Pipeline.stage(:gamma, ok_stage(& &1))

    assert {:ok, _, metadata} = Pipeline.run(pipeline, :val)
    assert Enum.map(metadata, & &1.stage) == [:alpha, :beta, :gamma]
  end