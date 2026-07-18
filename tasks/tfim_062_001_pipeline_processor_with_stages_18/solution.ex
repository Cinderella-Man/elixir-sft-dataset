  test "stages execute in the calling process and repeated runs are unaffected by prior runs" do
    caller = self()

    pipeline =
      Pipeline.new()
      |> Pipeline.stage(:report, fn v ->
        send(caller, {:ran_in, self()})
        {:ok, v + 1}
      end)
      |> Pipeline.stage(:finish, fn v -> {:ok, v * 2} end)

    assert {:ok, 4, meta_one} = Pipeline.run(pipeline, 1)
    assert_receive {:ran_in, ^caller}, 100

    assert {:ok, 4, meta_two} = Pipeline.run(pipeline, 1)
    assert_receive {:ran_in, ^caller}, 100

    assert Enum.map(meta_one, & &1.stage) == Enum.map(meta_two, & &1.stage)
    refute_receive {:ran_in, _}, 50
  end