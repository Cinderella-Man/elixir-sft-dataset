defmodule WorkflowTest do
  use ExUnit.Case, async: false

  # An order-lifecycle machine with two guards, expressed as data.
  defp order_machine do
    submit_guard = fn r ->
      items = Map.get(r, :items)
      is_list(items) and items != []
    end

    approve_guard = fn r ->
      by = Map.get(r, :approved_by)
      is_binary(by) and by != ""
    end

    Workflow.define(:draft, [
      {:submit, :draft, :submitted, submit_guard},
      {:approve, :submitted, :approved, approve_guard},
      {:reject, :submitted, :rejected},
      {:start, :approved, :in_progress},
      {:complete, :in_progress, :completed},
      {:cancel, :in_progress, :cancelled}
    ])
  end

  # A completely different machine to prove the engine is generic.
  defp door_machine do
    Workflow.define(:closed, [
      {:open, :closed, :opened},
      {:close, :opened, :closed},
      {:lock, :closed, :locked},
      {:unlock, :locked, :closed}
    ])
  end

  # -------------------------------------------------------
  # define / states
  # -------------------------------------------------------

  test "states/1 lists all distinct states of the order machine" do
    states = Workflow.states(order_machine())

    for s <- [:draft, :submitted, :approved, :in_progress, :completed, :rejected, :cancelled] do
      assert s in states
    end

    assert length(Enum.uniq(states)) == 7
  end

  test "states/1 for the door machine" do
    states = Workflow.states(door_machine())
    assert Enum.sort(Enum.uniq(states)) == [:closed, :locked, :opened]
  end

  test "define raises on duplicate event/from pair" do
    assert_raise ArgumentError, fn ->
      Workflow.define(:a, [{:go, :a, :b}, {:go, :a, :c}])
    end
  end

  test "define raises on malformed transition spec" do
    assert_raise ArgumentError, fn ->
      Workflow.define(:a, [{:go, :a}])
    end
  end

  test "define raises when guard is not a 1-arity function" do
    assert_raise ArgumentError, fn ->
      Workflow.define(:a, [{:go, :a, :b, fn -> true end}])
    end
  end

  # -------------------------------------------------------
  # new
  # -------------------------------------------------------

  test "new/2 starts in the machine's initial state and merges attrs" do
    m = order_machine()
    rec = Workflow.new(m, %{items: [1], state: :completed, tag: 5})
    assert rec.state == :draft
    assert rec.items == [1]
    assert rec.tag == 5
  end

  test "new/2 respects a different machine's initial" do
    rec = Workflow.new(door_machine())
    assert rec.state == :closed
  end

  # -------------------------------------------------------
  # Happy path
  # -------------------------------------------------------

  test "walks the full order happy path" do
    m = order_machine()
    rec = Workflow.new(m, %{items: [:widget], approved_by: "mgr"})

    assert {:ok, rec} = Workflow.transition(m, rec, :submit)
    assert rec.state == :submitted

    assert {:ok, rec} = Workflow.transition(m, rec, :approve)
    assert rec.state == :approved

    assert {:ok, rec} = Workflow.transition(m, rec, :start)
    assert rec.state == :in_progress

    assert {:ok, rec} = Workflow.transition(m, rec, :complete)
    assert rec.state == :completed
  end

  test "door machine transitions independently" do
    m = door_machine()
    rec = Workflow.new(m)

    assert {:ok, rec} = Workflow.transition(m, rec, :lock)
    assert rec.state == :locked
    assert {:ok, rec} = Workflow.transition(m, rec, :unlock)
    assert rec.state == :closed
    assert {:ok, rec} = Workflow.transition(m, rec, :open)
    assert rec.state == :opened
  end

  test "transition preserves unrelated fields" do
    m = order_machine()
    rec = Workflow.new(m, %{items: [:a], meta: %{c: 1}})
    {:ok, rec} = Workflow.transition(m, rec, :submit)
    assert rec.meta == %{c: 1}
    assert rec.items == [:a]
  end

  # -------------------------------------------------------
  # Invalid transitions
  # -------------------------------------------------------

  test "wrong-stage and unknown events are invalid" do
    m = order_machine()
    rec = Workflow.new(m, %{items: [:a]})

    assert {:error, :invalid_transition, :draft, :approve} =
             Workflow.transition(m, rec, :approve)

    assert {:error, :invalid_transition, :draft, :teleport} =
             Workflow.transition(m, rec, :teleport)
  end

  test "terminal states (no outgoing edges) reject every event" do
    m = order_machine()
    completed = %{Workflow.new(m) | state: :completed}

    for event <- [:submit, :approve, :reject, :start, :complete, :cancel] do
      assert {:error, :invalid_transition, :completed, ^event} =
               Workflow.transition(m, completed, event)
    end
  end

  test "door machine: opened cannot be locked" do
    m = door_machine()
    opened = %{Workflow.new(m) | state: :opened}
    assert {:error, :invalid_transition, :opened, :lock} =
             Workflow.transition(m, opened, :lock)
  end

  # -------------------------------------------------------
  # Guards
  # -------------------------------------------------------

  test "guard failure returns guard_failed and leaves record unchanged" do
    m = order_machine()
    rec = Workflow.new(m, %{items: []})
    assert {:error, :guard_failed, :draft, :submit} =
             Workflow.transition(m, rec, :submit)
    assert rec.state == :draft
  end

  test "approve guard is enforced from the data-defined edge" do
    m = order_machine()
    rec = Workflow.new(m, %{items: [:a], approved_by: "boss"})
    {:ok, rec} = Workflow.transition(m, rec, :submit)

    assert {:ok, %{state: :approved}} = Workflow.transition(m, rec, :approve)

    bad = %{rec | approved_by: nil}
    assert {:error, :guard_failed, :submitted, :approve} =
             Workflow.transition(m, bad, :approve)
  end

  test "guardless edges always pass" do
    m = order_machine()
    rec = Workflow.new(m, %{items: [:a]})
    {:ok, rec} = Workflow.transition(m, rec, :submit)
    assert {:ok, %{state: :rejected}} = Workflow.transition(m, rec, :reject)
  end

  # -------------------------------------------------------
  # can?/3
  # -------------------------------------------------------

  test "can?/3 reflects edges and guards" do
    m = order_machine()
    ok = Workflow.new(m, %{items: [:a]})
    bad = Workflow.new(m, %{items: []})

    assert Workflow.can?(m, ok, :submit) == true
    assert Workflow.can?(m, bad, :submit) == false
    assert Workflow.can?(m, ok, :approve) == false
  end
end