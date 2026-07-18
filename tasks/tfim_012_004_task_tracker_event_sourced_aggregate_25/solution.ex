  test "full command sequence produces correct state and event history", %{agg: agg} do
    {:ok, _} = TaskAggregate.execute(agg, "a", {:create, "Deploy v2", :medium})
    {:ok, _} = TaskAggregate.execute(agg, "a", {:assign, "Charlie"})
    {:ok, _} = TaskAggregate.execute(agg, "a", {:start})

    # Re-opening a task that is in progress (not yet completed) must return :not_completed.
    {:error, :not_completed} = TaskAggregate.execute(agg, "a", {:reopen})

    {:ok, _} = TaskAggregate.execute(agg, "a", {:complete})
    {:ok, _} = TaskAggregate.execute(agg, "a", {:reopen})
    {:ok, _} = TaskAggregate.execute(agg, "a", {:assign, "Diana"})
    {:ok, _} = TaskAggregate.execute(agg, "a", {:start})
    {:ok, _} = TaskAggregate.execute(agg, "a", {:complete})

    state = TaskAggregate.state(agg, "a")
    assert state.title == "Deploy v2"
    assert state.assignee == "Diana"
    assert state.status == :completed
    assert state.priority == :medium

    events = TaskAggregate.events(agg, "a")
    assert length(events) == 8

    types = Enum.map(events, & &1.type)

    assert types == [
             :task_created,
             :task_assigned,
             :task_started,
             :task_completed,
             :task_reopened,
             :task_assigned,
             :task_started,
             :task_completed
           ]
  end