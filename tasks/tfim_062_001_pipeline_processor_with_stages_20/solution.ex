  test "duplicate stage names both run in insertion order and the failing one is named" do
    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:step, fn v -> {:ok, v <> "a"} end)
      |> Pipeline.stage(:step, fn v -> {:ok, v <> "b"} end)

    assert {:ok, "xab", metadata} = Pipeline.run(pipeline, "x")
    assert Enum.map(metadata, & &1.stage) == [:step, :step]

    failing =
      Pipeline.new()
      |> Pipeline.stage(:step, fn v -> {:ok, v} end)
      |> Pipeline.stage(:step, fn _ -> {:error, :second} end)

    assert {:error, :step, :second} = Pipeline.run(failing, "x")
  end