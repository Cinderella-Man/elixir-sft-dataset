  test "stage/3 leaves the original pipeline untouched so a base can be reused" do
    base = Pipeline.new() |> Pipeline.stage(:base, fn v -> {:ok, v + 1} end)

    left = Pipeline.stage(base, :left, fn v -> {:ok, v * 10} end)
    right = Pipeline.stage(base, :right, fn v -> {:ok, v * 100} end)

    assert {:ok, 2, base_meta} = Pipeline.run(base, 1)
    assert Enum.map(base_meta, & &1.stage) == [:base]

    assert {:ok, 20, left_meta} = Pipeline.run(left, 1)
    assert Enum.map(left_meta, & &1.stage) == [:base, :left]

    assert {:ok, 200, right_meta} = Pipeline.run(right, 1)
    assert Enum.map(right_meta, & &1.stage) == [:base, :right]
  end