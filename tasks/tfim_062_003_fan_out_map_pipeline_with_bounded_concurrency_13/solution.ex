  test "a failing sequential stage halts with a 3-tuple error" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:a, ok_stage(& &1))
      |> Pipeline.stage(:b, fn _ -> {:error, :boom} end)

    assert {:error, :b, :boom} = Pipeline.run(pipeline, 0)
  end