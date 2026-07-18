  test "start_link registers the process under the given :name option" do
    {:ok, _pid} = TaskAggregate.start_link(name: :task_agg_named_test)

    assert {:ok, [event]} =
             TaskAggregate.execute(
               :task_agg_named_test,
               "task:1",
               {:create, "Fix bug", :high}
             )

    assert event.type == :task_created
    assert TaskAggregate.state(:task_agg_named_test, "task:1").status == :created
  end