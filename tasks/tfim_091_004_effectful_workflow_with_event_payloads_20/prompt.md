# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule Workflow do
  @moduledoc """
  A finite state machine for an order lifecycle where each transition carries an
  event payload. Guards may inspect that payload, and successful transitions run
  effects that stamp payload-derived data onto the record.

  Purely functional: no processes, standard library only.
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

  @doc "Builds a new effectful workflow from `attrs`. Returns the workflow map."
  @spec new(map()) :: map()
  def new(attrs \\ %{}) when is_map(attrs) do
    Map.put(attrs, :state, :draft)
  end

  @spec states() :: [atom()]
  def states, do: @states

  @spec transition(map(), atom(), map()) ::
          {:ok, map()}
          | {:error, :invalid_transition, atom(), atom()}
          | {:error, :guard_failed, atom(), atom()}
  def transition(record, event, payload \\ %{})

  def transition(%{state: current} = record, event, payload) when is_map(payload) do
    case Map.fetch(@transitions, event) do
      {:ok, {^current, to}} ->
        if guard(event, record, payload) do
          updated =
            record
            |> Map.put(:state, to)
            |> effect(event, payload)

          {:ok, updated}
        else
          {:error, :guard_failed, current, event}
        end

      _ ->
        {:error, :invalid_transition, current, event}
    end
  end

  @spec can?(map(), atom(), map()) :: boolean()
  def can?(record, event, payload \\ %{}) do
    match?({:ok, _}, transition(record, event, payload))
  end

  # Guards: return true when the transition is permitted.

  defp guard(:submit, %{items: items}, _payload) when is_list(items) and items != [], do: true
  defp guard(:submit, _record, _payload), do: false

  defp guard(:approve, _record, %{approver: a}) when is_binary(a) and a != "", do: true
  defp guard(:approve, _record, _payload), do: false

  defp guard(:reject, _record, %{reason: r}) when is_binary(r) and r != "", do: true
  defp guard(:reject, _record, _payload), do: false

  defp guard(_event, _record, _payload), do: true

  # Effects: applied after the state change on success.

  defp effect(record, :approve, %{approver: a}), do: Map.put(record, :approved_by, a)

  defp effect(record, :reject, %{reason: r}), do: Map.put(record, :rejection_reason, r)

  defp effect(record, :complete, _payload), do: Map.put(record, :completed, true)

  defp effect(record, :cancel, %{reason: r}) when is_binary(r),
    do: Map.put(record, :cancelled_reason, r)

  defp effect(record, _event, _payload), do: record
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule WorkflowTest do
  use ExUnit.Case, async: false

  defp draft do
    Workflow.new(%{items: [:widget], note: "hi"})
  end

  defp submitted do
    {:ok, rec} = Workflow.transition(draft(), :submit)
    rec
  end

  # -------------------------------------------------------
  # Construction
  # -------------------------------------------------------

  test "new/0 starts in :draft" do
    assert %{state: :draft} = Workflow.new()
  end

  test "new/1 merges attrs and forces :draft" do
    rec = Workflow.new(%{items: [1], state: :completed, tag: 3})
    assert rec.state == :draft
    assert rec.items == [1]
    assert rec.tag == 3
  end

  test "states/0 lists all seven states" do
    states = Workflow.states()

    for s <- [:draft, :submitted, :approved, :in_progress, :completed, :rejected, :cancelled] do
      assert s in states
    end

    assert length(Enum.uniq(states)) == 7
  end

  # -------------------------------------------------------
  # Happy path with payloads + effects
  # -------------------------------------------------------

  test "full happy path applies payload effects" do
    rec = draft()

    assert {:ok, rec} = Workflow.transition(rec, :submit)
    assert rec.state == :submitted

    assert {:ok, rec} = Workflow.transition(rec, :approve, %{approver: "manager"})
    assert rec.state == :approved
    assert rec.approved_by == "manager"

    assert {:ok, rec} = Workflow.transition(rec, :start)
    assert rec.state == :in_progress

    assert {:ok, rec} = Workflow.transition(rec, :complete)
    assert rec.state == :completed
    assert rec.completed == true
  end

  test "reject stamps the rejection reason from the payload" do
    {:ok, rec} = Workflow.transition(submitted(), :reject, %{reason: "duplicate"})
    assert rec.state == :rejected
    assert rec.rejection_reason == "duplicate"
  end

  test "cancel with a reason stamps cancelled_reason" do
    rec = submitted()
    {:ok, rec} = Workflow.transition(rec, :approve, %{approver: "m"})
    {:ok, rec} = Workflow.transition(rec, :start)
    {:ok, rec} = Workflow.transition(rec, :cancel, %{reason: "customer changed mind"})
    assert rec.state == :cancelled
    assert rec.cancelled_reason == "customer changed mind"
  end

  test "cancel without a reason still succeeds and adds no reason field" do
    rec = submitted()
    {:ok, rec} = Workflow.transition(rec, :approve, %{approver: "m"})
    {:ok, rec} = Workflow.transition(rec, :start)
    {:ok, rec} = Workflow.transition(rec, :cancel)
    assert rec.state == :cancelled
    refute Map.has_key?(rec, :cancelled_reason)
  end

  test "transition preserves unrelated fields" do
    rec = Workflow.new(%{items: [:a], meta: %{c: "acme"}})
    {:ok, rec} = Workflow.transition(rec, :submit)
    assert rec.meta == %{c: "acme"}
    assert rec.items == [:a]
  end

  # -------------------------------------------------------
  # Guards driven by payload
  # -------------------------------------------------------

  test "approve guard requires a non-empty approver in the payload" do
    rec = submitted()

    for bad <- [%{}, %{approver: nil}, %{approver: ""}, %{approver: 123}] do
      assert {:error, :guard_failed, :submitted, :approve} =
               Workflow.transition(rec, :approve, bad)
    end

    assert {:ok, %{state: :approved}} =
             Workflow.transition(rec, :approve, %{approver: "ok"})
  end

  test "reject guard requires a non-empty reason in the payload" do
    rec = submitted()

    assert {:error, :guard_failed, :submitted, :reject} =
             Workflow.transition(rec, :reject, %{})

    assert {:error, :guard_failed, :submitted, :reject} =
             Workflow.transition(rec, :reject, %{reason: ""})

    assert {:ok, %{state: :rejected}} =
             Workflow.transition(rec, :reject, %{reason: "bad"})
  end

  test "submit guard is record-based and ignores the payload" do
    empty = Workflow.new(%{items: []})

    assert {:error, :guard_failed, :draft, :submit} =
             Workflow.transition(empty, :submit, %{whatever: 1})

    ok = Workflow.new(%{items: [:a]})
    assert {:ok, %{state: :submitted}} = Workflow.transition(ok, :submit)
  end

  test "guard failure leaves the record unchanged" do
    rec = submitted()

    assert {:error, :guard_failed, :submitted, :approve} =
             Workflow.transition(rec, :approve, %{})

    assert rec.state == :submitted
    refute Map.has_key?(rec, :approved_by)
  end

  # -------------------------------------------------------
  # Invalid transitions
  # -------------------------------------------------------

  test "wrong-stage and unknown events are invalid" do
    rec = draft()

    assert {:error, :invalid_transition, :draft, :approve} =
             Workflow.transition(rec, :approve, %{approver: "x"})

    assert {:error, :invalid_transition, :draft, :teleport} =
             Workflow.transition(rec, :teleport)
  end

  test "terminal states reject every event" do
    completed = %{Workflow.new(%{}) | state: :completed}

    for event <- [:submit, :approve, :reject, :start, :complete, :cancel] do
      assert {:error, :invalid_transition, :completed, ^event} =
               Workflow.transition(completed, event, %{approver: "x", reason: "y"})
    end
  end

  # -------------------------------------------------------
  # can?/3
  # -------------------------------------------------------

  test "can?/3 accounts for the payload" do
    rec = submitted()
    assert Workflow.can?(rec, :approve, %{approver: "m"}) == true
    assert Workflow.can?(rec, :approve, %{}) == false
    assert Workflow.can?(rec, :reject, %{reason: "r"}) == true
    assert Workflow.can?(rec, :reject) == false
  end

  test "can?/3 defaults payload to empty and does not mutate" do
    rec = draft()
    assert Workflow.can?(rec, :submit) == true
    assert rec.state == :draft
  end

  test "invalid edge reports invalid_transition even when the guard would fail" do
    rec = draft()

    assert {:error, :invalid_transition, :draft, :approve} =
             Workflow.transition(rec, :approve, %{})

    assert {:error, :invalid_transition, :draft, :reject} =
             Workflow.transition(rec, :reject, %{reason: ""})

    {:ok, rejected} = Workflow.transition(submitted(), :reject, %{reason: "dup"})

    assert {:error, :invalid_transition, :rejected, :approve} =
             Workflow.transition(rejected, :approve, %{approver: nil})
  end

  test "rejected and cancelled records built via the API reject every event" do
    {:ok, rejected} = Workflow.transition(submitted(), :reject, %{reason: "dup"})

    {:ok, rec} = Workflow.transition(submitted(), :approve, %{approver: "m"})
    {:ok, rec} = Workflow.transition(rec, :start)
    {:ok, cancelled} = Workflow.transition(rec, :cancel, %{reason: "stop"})

    events = [:submit, :approve, :reject, :start, :complete, :cancel]

    for event <- events do
      assert {:error, :invalid_transition, :rejected, ^event} =
               Workflow.transition(rejected, event, %{approver: "x", reason: "y"})

      assert {:error, :invalid_transition, :cancelled, ^event} =
               Workflow.transition(cancelled, event, %{approver: "x", reason: "y"})

      assert Workflow.can?(rejected, event, %{approver: "x", reason: "y"}) == false
      assert Workflow.can?(cancelled, event, %{approver: "x", reason: "y"}) == false
    end
  end

  test "cancel with a non-binary reason succeeds without stamping cancelled_reason" do
    # TODO
  end

  test "reject guard rejects nil and non-binary reasons in the payload" do
    rec = submitted()

    for bad <- [%{reason: nil}, %{reason: 123}, %{reason: :duplicate}, %{reason: ["a"]}] do
      assert {:error, :guard_failed, :submitted, :reject} =
               Workflow.transition(rec, :reject, bad)

      assert Workflow.can?(rec, :reject, bad) == false
    end

    refute Map.has_key?(rec, :rejection_reason)
  end

  test "approve, reject and complete effects preserve untouched fields" do
    base = Workflow.new(%{items: [:a], note: "hi", meta: %{c: "acme"}})
    {:ok, sub} = Workflow.transition(base, :submit)

    {:ok, rej} = Workflow.transition(sub, :reject, %{reason: "dup"})
    assert rej.rejection_reason == "dup"
    assert rej.note == "hi"
    assert rej.meta == %{c: "acme"}
    assert rej.items == [:a]

    {:ok, rec} = Workflow.transition(sub, :approve, %{approver: "manager"})
    assert rec.approved_by == "manager"
    assert rec.note == "hi"
    assert rec.meta == %{c: "acme"}

    {:ok, rec} = Workflow.transition(rec, :start)
    {:ok, rec} = Workflow.transition(rec, :complete, %{approver: "ignored"})
    assert rec.completed == true
    assert rec.approved_by == "manager"
    assert rec.note == "hi"
    assert rec.items == [:a]
  end

  test "can?/3 is false for wrong-stage and unknown events" do
    rec = draft()

    assert Workflow.can?(rec, :approve, %{approver: "m"}) == false
    assert Workflow.can?(rec, :complete) == false
    assert Workflow.can?(rec, :teleport, %{approver: "m"}) == false
    assert Workflow.can?(Workflow.new(%{items: []}), :submit) == false
    assert Workflow.can?(rec, :submit, %{ignored: 1}) == true
  end
end
```
