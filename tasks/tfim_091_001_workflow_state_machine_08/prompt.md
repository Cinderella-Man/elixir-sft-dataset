# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule Workflow do
  @moduledoc """
  A finite state machine for the lifecycle of an order.

  An order record is a plain map that always carries a `:state` key holding the
  current state atom. It moves through the following states:

      draft → submitted → approved → in_progress → completed

  with two side branches:

      submitted → rejected
      in_progress → cancelled

  The states `:completed`, `:rejected`, and `:cancelled` are terminal — no event
  can move an order out of them.

  This module is purely functional: it neither spawns nor relies on any
  processes, and it uses only the Elixir/OTP standard library.
  """

  @states [
    :draft,
    :submitted,
    :approved,
    :in_progress,
    :completed,
    :rejected,
    :cancelled
  ]

  # event => {from, to}
  @transitions %{
    submit: {:draft, :submitted},
    approve: {:submitted, :approved},
    reject: {:submitted, :rejected},
    start: {:approved, :in_progress},
    complete: {:in_progress, :completed},
    cancel: {:in_progress, :cancelled}
  }

  @doc """
  Build a new record.

  Returns `attrs` merged with `%{state: :draft}`. Any `:state` provided in
  `attrs` is overridden — a new record always starts in `:draft`.
  """
  @spec new(map()) :: map()
  def new(attrs \\ %{}) when is_map(attrs) do
    Map.put(attrs, :state, :draft)
  end

  @doc """
  Return the list of all seven state atoms.
  """
  @spec states() :: [atom()]
  def states, do: @states

  @doc """
  Attempt to apply `event` to `record`.

    * On success, returns `{:ok, updated_record}` with the `:state` field
      replaced by the destination state and all other fields preserved.
    * If `event` is not a valid transition out of the current state (including
      any event fired from a terminal state, or an unknown event), returns
      `{:error, :invalid_transition, current_state, event}`.
    * If the event is a valid edge but its guard rejects the record, returns
      `{:error, :guard_failed, current_state, event}`.
  """
  @spec transition(map(), atom()) ::
          {:ok, map()}
          | {:error, :invalid_transition, atom(), atom()}
          | {:error, :guard_failed, atom(), atom()}
  def transition(%{state: current} = record, event) do
    case Map.fetch(@transitions, event) do
      {:ok, {^current, to}} ->
        if guard(event, record) do
          {:ok, Map.put(record, :state, to)}
        else
          {:error, :guard_failed, current, event}
        end

      _ ->
        {:error, :invalid_transition, current, event}
    end
  end

  @doc """
  Return `true` if `transition(record, event)` would succeed, otherwise `false`.
  """
  @spec can?(map(), atom()) :: boolean()
  def can?(record, event) do
    match?({:ok, _}, transition(record, event))
  end

  # Guards: return true when the transition is permitted.

  defp guard(:submit, %{items: items}) when is_list(items) and items != [], do: true
  defp guard(:submit, _record), do: false

  defp guard(:approve, %{approved_by: approved_by})
       when is_binary(approved_by) and approved_by != "",
       do: true

  defp guard(:approve, _record), do: false

  # All other transitions have no guard and always pass.
  defp guard(_event, _record), do: true
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule WorkflowTest do
  use ExUnit.Case, async: false

  # Convenience builders for records that satisfy the guards.
  defp submittable_draft do
    Workflow.new(%{items: [:widget], approved_by: nil, note: "hello"})
  end

  defp approvable_submitted do
    {:ok, rec} = Workflow.transition(submittable_draft(), :submit)
    %{rec | approved_by: "manager"}
  end

  # -------------------------------------------------------
  # Construction
  # -------------------------------------------------------

  test "new/0 starts in :draft" do
    assert %{state: :draft} = Workflow.new()
  end

  test "new/1 merges attrs and forces :draft" do
    rec = Workflow.new(%{items: [1, 2], approved_by: "x", state: :completed})
    assert rec.state == :draft
    assert rec.items == [1, 2]
    assert rec.approved_by == "x"
  end

  test "states/0 lists all seven states" do
    states = Workflow.states()
    for s <- [:draft, :submitted, :approved, :in_progress, :completed, :rejected, :cancelled] do
      assert s in states, "expected #{inspect(s)} in #{inspect(states)}"
    end
    assert length(Enum.uniq(states)) == 7
  end

  # -------------------------------------------------------
  # Happy path walk
  # -------------------------------------------------------

  test "walks the full happy path draft -> completed" do
    rec = submittable_draft()

    assert {:ok, rec} = Workflow.transition(rec, :submit)
    assert rec.state == :submitted

    rec = %{rec | approved_by: "manager"}
    assert {:ok, rec} = Workflow.transition(rec, :approve)
    assert rec.state == :approved

    assert {:ok, rec} = Workflow.transition(rec, :start)
    assert rec.state == :in_progress

    assert {:ok, rec} = Workflow.transition(rec, :complete)
    assert rec.state == :completed
  end

  test "reject side branch: submitted -> rejected" do
    rec = approvable_submitted()
    assert {:ok, rec} = Workflow.transition(rec, :reject)
    assert rec.state == :rejected
  end

  test "cancel side branch: in_progress -> cancelled" do
    rec = approvable_submitted()
    {:ok, rec} = Workflow.transition(rec, :approve)
    {:ok, rec} = Workflow.transition(rec, :start)
    assert rec.state == :in_progress

    assert {:ok, rec} = Workflow.transition(rec, :cancel)
    assert rec.state == :cancelled
  end

  # -------------------------------------------------------
  # Field preservation
  # -------------------------------------------------------

  test "transition preserves unrelated fields" do
    # TODO
  end

  # -------------------------------------------------------
  # Invalid transitions
  # -------------------------------------------------------

  test "invalid event from draft returns invalid_transition" do
    rec = submittable_draft()
    assert {:error, :invalid_transition, :draft, :approve} =
             Workflow.transition(rec, :approve)

    assert {:error, :invalid_transition, :draft, :complete} =
             Workflow.transition(rec, :complete)

    assert {:error, :invalid_transition, :draft, :cancel} =
             Workflow.transition(rec, :cancel)
  end

  test "unknown event is an invalid transition" do
    rec = submittable_draft()
    assert {:error, :invalid_transition, :draft, :teleport} =
             Workflow.transition(rec, :teleport)
  end

  test "wrong-stage valid event still returns invalid_transition" do
    rec = approvable_submitted()
    # :start is only valid from :approved, not :submitted
    assert {:error, :invalid_transition, :submitted, :start} =
             Workflow.transition(rec, :start)

    # :submit only valid from :draft
    assert {:error, :invalid_transition, :submitted, :submit} =
             Workflow.transition(rec, :submit)
  end

  test "terminal states reject every event" do
    # completed
    completed = %{Workflow.new(%{}) | state: :completed}
    for event <- [:submit, :approve, :reject, :start, :complete, :cancel] do
      assert {:error, :invalid_transition, :completed, ^event} =
               Workflow.transition(completed, event)
    end

    # rejected
    rejected = %{Workflow.new(%{}) | state: :rejected}
    assert {:error, :invalid_transition, :rejected, :approve} =
             Workflow.transition(rejected, :approve)

    # cancelled
    cancelled = %{Workflow.new(%{}) | state: :cancelled}
    assert {:error, :invalid_transition, :cancelled, :start} =
             Workflow.transition(cancelled, :start)
  end

  # -------------------------------------------------------
  # Guards
  # -------------------------------------------------------

  test "submit guard fails on empty items" do
    rec = Workflow.new(%{items: []})
    assert {:error, :guard_failed, :draft, :submit} =
             Workflow.transition(rec, :submit)
  end

  test "submit guard fails on missing items" do
    rec = Workflow.new(%{})
    assert {:error, :guard_failed, :draft, :submit} =
             Workflow.transition(rec, :submit)
  end

  test "submit guard fails on non-list items" do
    rec = Workflow.new(%{items: "not a list"})
    assert {:error, :guard_failed, :draft, :submit} =
             Workflow.transition(rec, :submit)
  end

  test "submit guard passes on non-empty items" do
    rec = Workflow.new(%{items: [:only_one]})
    assert {:ok, %{state: :submitted}} = Workflow.transition(rec, :submit)
  end

  test "approve guard fails when approved_by is nil/missing/blank" do
    base = approvable_submitted()

    assert {:error, :guard_failed, :submitted, :approve} =
             Workflow.transition(%{base | approved_by: nil}, :approve)

    assert {:error, :guard_failed, :submitted, :approve} =
             Workflow.transition(%{base | approved_by: ""}, :approve)

    assert {:error, :guard_failed, :submitted, :approve} =
             Workflow.transition(%{base | approved_by: 123}, :approve)

    assert {:error, :guard_failed, :submitted, :approve} =
             Workflow.transition(Map.delete(base, :approved_by), :approve)
  end

  test "approve guard passes with a non-empty approver string" do
    rec = approvable_submitted()
    assert {:ok, %{state: :approved}} = Workflow.transition(rec, :approve)
  end

  test "guard failure leaves the record unchanged" do
    rec = Workflow.new(%{items: []})
    assert {:error, :guard_failed, :draft, :submit} =
             Workflow.transition(rec, :submit)
    # calling again yields the same result — no mutation happened
    assert {:error, :guard_failed, :draft, :submit} =
             Workflow.transition(rec, :submit)
  end

  # -------------------------------------------------------
  # can?/2
  # -------------------------------------------------------

  test "can?/2 reflects valid edges and guards" do
    draft_ok = submittable_draft()
    draft_bad = Workflow.new(%{items: []})

    assert Workflow.can?(draft_ok, :submit) == true
    assert Workflow.can?(draft_bad, :submit) == false
    assert Workflow.can?(draft_ok, :approve) == false

    submitted = approvable_submitted()
    assert Workflow.can?(submitted, :approve) == true
    assert Workflow.can?(submitted, :reject) == true
    assert Workflow.can?(%{submitted | approved_by: nil}, :approve) == false

    completed = %{Workflow.new(%{}) | state: :completed}
    assert Workflow.can?(completed, :complete) == false
  end

  test "can? does not mutate or transition the record" do
    rec = submittable_draft()
    assert Workflow.can?(rec, :submit) == true
    # record is still in draft
    assert rec.state == :draft
  end
end
```
