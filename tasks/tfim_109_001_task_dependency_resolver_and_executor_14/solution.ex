  test "reports a dependency that was never submitted" do
    TaskRunner.submit(:runner, :b, depends_on: [:a], func: task(:b))

    assert {:error, {:unknown_dependencies, missing}} =
             TaskRunner.run_all(:runner)

    assert :a in missing
  end