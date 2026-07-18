  test "submitting alone never executes a task func" do
    parent = self()
    start_runner(2)

    BoundedRunner.submit(:runner, :lazy,
      func: fn ->
        send(parent, :ran)
        :done
      end
    )

    refute_receive :ran, 300
    assert Tracker.events() == []

    assert {:ok, %{lazy: :done}} = BoundedRunner.run_all(:runner)
    assert_receive :ran, 500
  end