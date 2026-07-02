  test "empty runner returns an empty result map" do
    assert {:ok, results} = DataFlowRunner.run_all(:runner)
    assert results == %{}
  end