  test "data flows through a diamond DAG" do
    #      a
    #     / \
    #    b   c
    #     \ /
    #      d
    DataFlowRunner.submit(:runner, :a, func: fn _ -> 1 end)
    DataFlowRunner.submit(:runner, :b, depends_on: [:a], func: fn %{a: v} -> v * 2 end)
    DataFlowRunner.submit(:runner, :c, depends_on: [:a], func: fn %{a: v} -> v * 3 end)

    DataFlowRunner.submit(:runner, :d,
      depends_on: [:b, :c],
      func: fn %{b: b, c: c} -> b + c end
    )

    assert {:ok, results} = DataFlowRunner.run_all(:runner)
    assert results == %{a: 1, b: 2, c: 3, d: 5}
  end