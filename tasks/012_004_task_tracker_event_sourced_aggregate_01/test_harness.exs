defmodule TaskAggregateTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, pid} = TaskAggregate.start_link([])
    %{agg: pid}
  end

  # -------------------------------------------------------
  # Creating a task
  # -------------------------------------------------------

  test "create produces a :task_created event", %{agg: agg} do
    assert {:ok, [event]} = TaskAggregate.execute(agg, "task:1", {:create, "Fix bug", :high})
    assert event.type == :task_created
  end

  test "state after create has correct title, assignee, status, and priority", %{agg: agg} do
    TaskAggregate.execute(agg, "task:1", {:create, "Fix bug", :high})

    state = TaskAggregate.state(agg, "task:1")
    assert state.title == "Fix bug"
    assert state.assignee == nil
    assert state.status == :created
    assert state.priority == :high
  end

  test "creating an already-existing task fails", %{agg: agg} do
    TaskAggregate.execute(agg, "task:1", {:create, "Fix bug", :high})
    assert {:error, :already_exists} = TaskAggregate.execute(agg, "task:1", {:create, "Other", :low})
  end

  test "creating with invalid priority fails", %{agg: agg} do
    assert {:error, :invalid_priority} = TaskAggregate.execute(agg, "task:1", {:create, "Fix bug", :urgent})
  end

  # -------------------------------------------------------
  # Assigning a task
  # -------------------------------------------------------

  test "assign sets the assignee", %{agg: agg} do
    TaskAggregate.execute(agg, "task:1", {:create, "Fix bug", :high})
    assert {:ok, [event]} = TaskAggregate.execute(agg, "task:1", {:assign, "Alice"})
    assert event.type == :task_assigned

    state = TaskAggregate.state(agg, "task:1")
    assert state.assignee == "Alice"
  end

  test "reassigning to a different person succeeds", %{agg: agg} do
    TaskAggregate.execute(agg, "task:1", {:create, "Fix bug", :high})
    TaskAggregate.execute(agg, "task:1", {:assign, "Alice"})
    assert {:ok, _} = TaskAggregate.execute(agg, "task:1", {:assign, "Bob"})

    assert TaskAggregate.state(agg, "task:1").assignee == "Bob"
  end

  test "assign on non-existent task fails", %{agg: agg} do
    assert {:error, :not_found} = TaskAggregate.execute(agg, "task:1", {:assign, "Alice"})
  end

  test "assign on completed task fails", %{agg: agg} do
    TaskAggregate.execute(agg, "task:1", {:create, "Fix bug", :high})
    TaskAggregate.execute(agg, "task:1", {:assign, "Alice"})
    TaskAggregate.execute(agg, "task:1", {:start})
    TaskAggregate.execute(agg, "task:1", {:complete})
    assert {:error, :already_completed} = TaskAggregate.execute(agg, "task:1", {:assign, "Bob"})
  end

  # -------------------------------------------------------
  # Starting a task
  # -------------------------------------------------------

  test "start moves status to :in_progress", %{agg: agg} do
    TaskAggregate.execute(agg, "task:1", {:create, "Fix bug", :high})
    TaskAggregate.execute(agg, "task:1", {:assign, "Alice"})
    assert {:ok, [event]} = TaskAggregate.execute(agg, "task:1", {:start})
    assert event.type == :task_started

    assert TaskAggregate.state(agg, "task:1").status == :in_progress
  end

  test "start on non-existent task fails", %{agg: agg} do
    assert {:error, :not_found} = TaskAggregate.execute(agg, "task:1", {:start})
  end

  test "start on unassigned task fails", %{agg: agg} do
    TaskAggregate.execute(agg, "task:1", {:create, "Fix bug", :high})
    assert {:error, :not_assigned} = TaskAggregate.execute(agg, "task:1", {:start})
  end

  test "start on already-in-progress task fails", %{agg: agg} do
    TaskAggregate.execute(agg, "task:1", {:create, "Fix bug", :high})
    TaskAggregate.execute(agg, "task:1", {:assign, "Alice"})
    TaskAggregate.execute(agg, "task:1", {:start})
    assert {:error, :already_started} = TaskAggregate.execute(agg, "task:1", {:start})
  end

  # -------------------------------------------------------
  # Completing a task
  # -------------------------------------------------------

  test "complete moves status to :completed", %{agg: agg} do
    TaskAggregate.execute(agg, "task:1", {:create, "Fix bug", :high})
    TaskAggregate.execute(agg, "task:1", {:assign, "Alice"})
    TaskAggregate.execute(agg, "task:1", {:start})
    assert {:ok, [event]} = TaskAggregate.execute(agg, "task:1", {:complete})
    assert event.type == :task_completed

    assert TaskAggregate.state(agg, "task:1").status == :completed
  end

  test "complete on non-existent task fails", %{agg: agg} do
    assert {:error, :not_found} = TaskAggregate.execute(agg, "task:1", {:complete})
  end

  test "complete on task not in progress fails", %{agg: agg} do
    TaskAggregate.execute(agg, "task:1", {:create, "Fix bug", :high})
    TaskAggregate.execute(agg, "task:1", {:assign, "Alice"})
    assert {:error, :not_in_progress} = TaskAggregate.execute(agg, "task:1", {:complete})
  end

  # -------------------------------------------------------
  # Reopening a task
  # -------------------------------------------------------

  test "reopen moves completed task back to :created with nil assignee", %{agg: agg} do
    TaskAggregate.execute(agg, "task:1", {:create, "Fix bug", :high})
    TaskAggregate.execute(agg, "task:1", {:assign, "Alice"})
    TaskAggregate.execute(agg, "task:1", {:start})
    TaskAggregate.execute(agg, "task:1", {:complete})
    assert {:ok, [event]} = TaskAggregate.execute(agg, "task:1", {:reopen})
    assert event.type == :task_reopened

    state = TaskAggregate.state(agg, "task:1")
    assert state.status == :created
    assert state.assignee == nil
  end

  test "reopen on non-existent task fails", %{agg: agg} do
    assert {:error, :not_found} = TaskAggregate.execute(agg, "task:1", {:reopen})
  end

  test "reopen on non-completed task fails", %{agg: agg} do
    TaskAggregate.execute(agg, "task:1", {:create, "Fix bug", :high})
    TaskAggregate.execute(agg, "task:1", {:assign, "Alice"})
    TaskAggregate.execute(agg, "task:1", {:start})
    assert {:error, :not_completed} = TaskAggregate.execute(agg, "task:1", {:reopen})
  end

  # -------------------------------------------------------
  # Event history
  # -------------------------------------------------------

  test "events returns full ordered history", %{agg: agg} do
    TaskAggregate.execute(agg, "task:1", {:create, "Fix bug", :high})
    TaskAggregate.execute(agg, "task:1", {:assign, "Alice"})
    TaskAggregate.execute(agg, "task:1", {:start})

    events = TaskAggregate.events(agg, "task:1")
    assert length(events) == 3

    assert Enum.map(events, & &1.type) == [
             :task_created,
             :task_assigned,
             :task_started
           ]
  end

  test "failed commands produce no events", %{agg: agg} do
    TaskAggregate.execute(agg, "task:1", {:create, "Fix bug", :high})
    TaskAggregate.execute(agg, "task:1", {:start})
    TaskAggregate.execute(agg, "task:1", {:complete})

    events = TaskAggregate.events(agg, "task:1")
    assert length(events) == 1
    assert hd(events).type == :task_created
  end

  test "events for unknown aggregate returns empty list", %{agg: agg} do
    assert TaskAggregate.events(agg, "nonexistent") == []
  end

  # -------------------------------------------------------
  # State queries
  # -------------------------------------------------------

  test "state for unknown aggregate returns nil", %{agg: agg} do
    assert TaskAggregate.state(agg, "nonexistent") == nil
  end

  # -------------------------------------------------------
  # Aggregate independence
  # -------------------------------------------------------

  test "different aggregate ids are completely independent", %{agg: agg} do
    TaskAggregate.execute(agg, "task:1", {:create, "Fix bug", :high})
    TaskAggregate.execute(agg, "task:1", {:assign, "Alice"})
    TaskAggregate.execute(agg, "task:1", {:start})

    TaskAggregate.execute(agg, "task:2", {:create, "Add feature", :low})

    assert TaskAggregate.state(agg, "task:1").status == :in_progress
    assert TaskAggregate.state(agg, "task:2").status == :created

    assert length(TaskAggregate.events(agg, "task:1")) == 3
    assert length(TaskAggregate.events(agg, "task:2")) == 1
  end

  # -------------------------------------------------------
  # Full scenario — replay verification
  # -------------------------------------------------------

  test "full command sequence produces correct state and event history", %{agg: agg} do
    {:ok, _} = TaskAggregate.execute(agg, "a", {:create, "Deploy v2", :medium})
    {:ok, _} = TaskAggregate.execute(agg, "a", {:assign, "Charlie"})
    {:ok, _} = TaskAggregate.execute(agg, "a", {:start})
    {:error, :not_in_progress} = TaskAggregate.execute(agg, "a", {:reopen})
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
    # 8 successful commands = 8 events
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

  # -------------------------------------------------------
  # Event content
  # -------------------------------------------------------

  test "events carry relevant data", %{agg: agg} do
    TaskAggregate.execute(agg, "task:1", {:create, "Fix bug", :high})
    TaskAggregate.execute(agg, "task:1", {:assign, "Alice"})
    TaskAggregate.execute(agg, "task:1", {:start})

    [created, assigned, started] = TaskAggregate.events(agg, "task:1")

    assert created.type == :task_created
    assert Map.has_key?(created, :title)
    assert Map.has_key?(created, :priority)

    assert assigned.type == :task_assigned
    assert assigned.assignee == "Alice"

    assert started.type == :task_started
  end
end
