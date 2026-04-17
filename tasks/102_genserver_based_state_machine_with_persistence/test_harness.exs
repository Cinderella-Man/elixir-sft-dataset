defmodule StateMachineTest do
  use ExUnit.Case, async: false

  # ---------------------------------------------------------------------------
  # Minimal in-memory Ecto repo shim for deterministic testing
  # ---------------------------------------------------------------------------
  #
  # If you wire up a real SQLite/Postgres repo in your test config, replace
  # `TestRepo` below with your actual repo and remove the FakeRepo block.
  #
  # The shim below satisfies the surface area that StateMachine uses so the
  # tests run without any database process.
  # ---------------------------------------------------------------------------

  defmodule FakeRepo do
    @moduledoc """
    A process-backed in-memory store that mimics the Ecto Repo API used by
    StateMachine: `insert/1`, `all/2`, and `one/2` with basic Ecto.Query support.
    """
    use Agent

    def start_link(_opts \\ []) do
      Agent.start_link(fn -> [] end, name: __MODULE__)
    end

    # Inserts a struct that has an Ecto schema (EntityTransition)
    def insert(changeset_or_struct) do
      record =
        case changeset_or_struct do
          %Ecto.Changeset{} = cs -> Ecto.Changeset.apply_changes(cs)
          struct -> struct
        end

      record = %{record | id: System.unique_integer([:positive, :monotonic]),
                          inserted_at: DateTime.utc_now()}

      Agent.update(__MODULE__, &[record | &1])
      {:ok, record}
    end

    # Supports `all(query)` — returns rows that match entity_id if a where clause is present.
    # For our tests we only need `Repo.all(from t in EntityTransition, where: t.entity_id == ^id,
    #   order_by: [asc: t.id])`.
    def all(query, _opts \\ []) do
      rows = Agent.get(__MODULE__, & &1)

      rows
      |> filter_by_query(query)
      |> Enum.sort_by(& &1.id)
    end

    # Supports `one(query)` — returns last inserted row for entity or nil.
    def one(query, _opts \\ []) do
      rows = Agent.get(__MODULE__, & &1)

      rows
      |> filter_by_query(query)
      |> Enum.sort_by(& &1.id, :desc)
      |> List.first()
    end

    defp filter_by_query(rows, %Ecto.Query{} = query) do
      # Extract the entity_id binding from the first where-clause parameter, if any
      entity_id =
        query.wheres
        |> List.first()
        |> case do
          nil -> nil
          where -> extract_entity_id(where.params)
        end

      if entity_id do
        Enum.filter(rows, &(&1.entity_id == entity_id))
      else
        rows
      end
    end

    defp filter_by_query(rows, _), do: rows

    defp extract_entity_id(params) when is_list(params) do
      params
      |> Enum.find_value(fn
        {val, _type} when is_binary(val) -> val
        _ -> nil
      end)
    end

    defp extract_entity_id(_), do: nil
  end

  # ---------------------------------------------------------------------------
  # Setup
  # ---------------------------------------------------------------------------

  setup do
    start_supervised!(FakeRepo)
    {:ok, pid} = StateMachine.start_link(repo: FakeRepo)
    %{sm: pid}
  end

  # ---------------------------------------------------------------------------
  # Starting entities
  # ---------------------------------------------------------------------------

  test "start/2 returns :pending for a brand-new entity", %{sm: sm} do
    assert {:ok, :pending} = StateMachine.start(sm, "order:1")
  end

  test "start/2 for the same entity twice returns the same state", %{sm: sm} do
    {:ok, :pending} = StateMachine.start(sm, "order:1")
    assert {:ok, :pending} = StateMachine.start(sm, "order:1")
  end

  test "start/2 re-hydrates state from DB after the in-memory map is cleared", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:42")
    {:ok, :confirmed} = StateMachine.transition(sm, "order:42", :confirm)
    {:ok, :shipped} = StateMachine.transition(sm, "order:42", :ship)

    # Start a *new* GenServer backed by the same FakeRepo
    {:ok, sm2} = StateMachine.start_link(repo: FakeRepo)

    # Entity was never started in sm2, so it must hydrate from DB
    assert {:ok, :shipped} = StateMachine.start(sm2, "order:42")
  end

  # ---------------------------------------------------------------------------
  # get_state
  # ---------------------------------------------------------------------------

  test "get_state/2 returns :not_found for unknown entity", %{sm: sm} do
    assert {:error, :not_found} = StateMachine.get_state(sm, "order:nope")
  end

  test "get_state/2 reflects the current in-memory state", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:1")
    {:ok, _} = StateMachine.transition(sm, "order:1", :confirm)
    assert {:ok, :confirmed} = StateMachine.get_state(sm, "order:1")
  end

  # ---------------------------------------------------------------------------
  # Happy-path transitions
  # ---------------------------------------------------------------------------

  test "full happy path: pending → confirmed → shipped → delivered", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:1")

    assert {:ok, :confirmed} = StateMachine.transition(sm, "order:1", :confirm)
    assert {:ok, :confirmed} = StateMachine.get_state(sm, "order:1")

    assert {:ok, :shipped} = StateMachine.transition(sm, "order:1", :ship)
    assert {:ok, :delivered} = StateMachine.transition(sm, "order:1", :deliver)

    assert {:ok, :delivered} = StateMachine.get_state(sm, "order:1")
  end

  test "cancellation from :pending", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:2")
    assert {:ok, :cancelled} = StateMachine.transition(sm, "order:2", :cancel)
  end

  test "cancellation from :confirmed", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:3")
    {:ok, _} = StateMachine.transition(sm, "order:3", :confirm)
    assert {:ok, :cancelled} = StateMachine.transition(sm, "order:3", :cancel)
  end

  # ---------------------------------------------------------------------------
  # Invalid transitions
  # ---------------------------------------------------------------------------

  test "invalid event returns :invalid_transition and does not change state", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:1")
    {:ok, _} = StateMachine.transition(sm, "order:1", :confirm)

    # :ship from :confirmed is valid, but :deliver from :confirmed is not
    assert {:error, :invalid_transition} =
             StateMachine.transition(sm, "order:1", :deliver)

    # State must be unchanged
    assert {:ok, :confirmed} = StateMachine.get_state(sm, "order:1")
  end

  test "transitioning a terminal state is invalid", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:1")
    {:ok, _} = StateMachine.transition(sm, "order:1", :cancel)

    assert {:error, :invalid_transition} =
             StateMachine.transition(sm, "order:1", :confirm)

    assert {:ok, :cancelled} = StateMachine.get_state(sm, "order:1")
  end

  test "transition on unknown entity returns :not_found", %{sm: sm} do
    assert {:error, :not_found} =
             StateMachine.transition(sm, "order:unknown", :confirm)
  end

  test "invalid transition does not write to DB", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:1")

    {:error, :invalid_transition} =
      StateMachine.transition(sm, "order:1", :ship)

    assert {:ok, []} = StateMachine.history(sm, "order:1")
  end

  # ---------------------------------------------------------------------------
  # Persistence / history
  # ---------------------------------------------------------------------------

  test "history/2 records every transition in order", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:1")
    {:ok, _} = StateMachine.transition(sm, "order:1", :confirm)
    {:ok, _} = StateMachine.transition(sm, "order:1", :ship)

    assert {:ok, [first, second]} = StateMachine.history(sm, "order:1")

    assert first.event == :confirm
    assert first.from_state == :pending
    assert first.to_state == :confirmed

    assert second.event == :ship
    assert second.from_state == :confirmed
    assert second.to_state == :shipped
  end

  test "history/2 for unknown entity returns empty list", %{sm: sm} do
    assert {:ok, []} = StateMachine.history(sm, "order:nobody")
  end

  test "history/2 is scoped per entity", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:A")
    {:ok, _} = StateMachine.start(sm, "order:B")
    {:ok, _} = StateMachine.transition(sm, "order:A", :confirm)
    {:ok, _} = StateMachine.transition(sm, "order:B", :cancel)

    assert {:ok, [%{event: :confirm}]} = StateMachine.history(sm, "order:A")
    assert {:ok, [%{event: :cancel}]} = StateMachine.history(sm, "order:B")
  end

  # ---------------------------------------------------------------------------
  # State recovery after simulated restart
  # ---------------------------------------------------------------------------

  test "state survives GenServer restart and is recovered from DB", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:99")
    {:ok, _} = StateMachine.transition(sm, "order:99", :confirm)
    {:ok, _} = StateMachine.transition(sm, "order:99", :ship)

    # Kill the original GenServer (simulate crash/restart)
    GenServer.stop(sm)

    # Boot a fresh one backed by the same repo
    {:ok, sm2} = StateMachine.start_link(repo: FakeRepo)

    # Re-hydrate from DB
    assert {:ok, :shipped} = StateMachine.start(sm2, "order:99")

    # And it should accept further valid transitions from recovered state
    assert {:ok, :delivered} = StateMachine.transition(sm2, "order:99", :deliver)
  end

  # ---------------------------------------------------------------------------
  # Concurrency — concurrent callers serialize correctly
  # ---------------------------------------------------------------------------

  test "concurrent transitions on the same entity serialize without corruption", %{sm: sm} do
    {:ok, _} = StateMachine.start(sm, "order:concurrent")

    # Fire many concurrent callers; only the first :confirm should succeed,
    # the rest should get :invalid_transition (already confirmed) or
    # :invalid_transition (not a valid event from :pending).
    tasks =
      for _ <- 1..20 do
        Task.async(fn ->
          StateMachine.transition(sm, "order:concurrent", :confirm)
        end)
      end

    results = Task.await_many(tasks)

    oks = Enum.filter(results, &match?({:ok, _}, &1))
    errors = Enum.filter(results, &match?({:error, :invalid_transition}, &1))

    # Exactly one transition should have succeeded
    assert length(oks) == 1
    assert {:ok, :confirmed} = hd(oks)

    # All others should have gotten :invalid_transition
    assert length(errors) == 19
  end

  test "concurrent transitions on *different* entities don't interfere", %{sm: sm} do
    for i <- 1..10 do
      StateMachine.start(sm, "order:par:#{i}")
    end

    tasks =
      for i <- 1..10 do
        Task.async(fn ->
          StateMachine.transition(sm, "order:par:#{i}", :confirm)
        end)
      end

    results = Task.await_many(tasks)
    assert Enum.all?(results, &match?({:ok, :confirmed}, &1))
  end
end
