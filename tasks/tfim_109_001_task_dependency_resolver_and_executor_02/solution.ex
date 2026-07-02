  test "empty runner returns an empty result map" do
    assert {:ok, results} = TaskRunner.run_all(:runner)
    assert results == %{}
  end