  test "stage/3 rejects a non-atom stage name" do
    assert_raise FunctionClauseError, fn ->
      Pipeline.stage(Pipeline.new(), "not_an_atom", ok_stage(& &1))
    end
  end