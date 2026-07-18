  test "non-atom task ids such as strings and tuples are supported" do
    DataFlowRunner.submit(:runner, "src", func: fn _ -> 7 end)

    DataFlowRunner.submit(:runner, {:sink, 1},
      depends_on: ["src"],
      func: fn inputs -> Map.fetch!(inputs, "src") * 2 end
    )

    assert {:ok, results} = DataFlowRunner.run_all(:runner)
    assert results == %{"src" => 7, {:sink, 1} => 14}
  end