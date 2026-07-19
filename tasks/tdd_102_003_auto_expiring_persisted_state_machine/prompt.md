# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule StateMachineTest do
  use ExUnit.Case, async: false

  @repo StateMachine.Repo

  setup_all do
    ensure_repo_started()
    ensure_migrated()
    :ok
  end

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(@repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    # Default server: no TTL configured, so automatic expiry is disabled.
    {:ok, pid} = StateMachine.start_link(repo: @repo)
    %{sm: pid}
  end

  # ---------------------------------------------------------------------------
  # Base behaviour (TTL disabled)
  # ---------------------------------------------------------------------------

  test "start/2 returns :pending for a brand-new entity", %{sm: sm} do
    assert {:ok, :pending} = StateMachine.start(sm, "order:1")
  end

  test "get_state/2 returns :not_found for unknown entity", %{sm: sm} do
    assert {:error, :not_found} = StateMachine.get_state(sm, "order:nope")
  end

  test "full happy path: pending -> confirmed -> shipped -> delivered", %{sm: sm} do
    {:ok, :pending} = StateMachine.start(sm, "order:1")
    assert {:ok, :confirmed} = StateMachine.transition(sm, "order:1", :confirm)
    assert {:ok, :shipped} = StateMachine.transition(sm, "order:1", :ship)
    assert {:ok, :delivered} = StateMachine.transition(sm, "order:1", :deliver)
    assert {:ok, :delivered} = StateMachine.get_state(sm, "order:1")
  end

  test "invalid event returns :invalid_transition and does not change state", %{sm: sm} do
    {:ok, :pending} = StateMachine.start(sm, "order:1")
    assert {:error, :invalid_transition} = StateMachine.transition(sm, "order:1", :ship)
    assert {:ok, :pending} = StateMachine.get_state(sm, "order:1")
  end

  test "transition on unknown entity returns :not_found", %{sm: sm} do
    assert {:error, :not_found} = StateMachine.transition(sm, "order:unknown", :confirm)
  end

  test "with TTL disabled a pending entity stays pending", %{sm: sm} do
    {:ok, :pending} = StateMachine.start(sm, "order:stays")
    Process.sleep(120)
    assert {:ok, :pending} = StateMachine.get_state(sm, "order:stays")
    assert {:ok, []} = StateMachine.history(sm, "order:stays")
  end

  # ---------------------------------------------------------------------------
  # Automatic expiry
  # ---------------------------------------------------------------------------

  test "a pending entity auto-cancels after the TTL and records an :expire transition" do
    {:ok, sm} = StateMachine.start_link(repo: @repo, pending_ttl_ms: 60)
    {:ok, :pending} = StateMachine.start(sm, "order:exp")

    Process.sleep(180)

    assert {:ok, :cancelled} = StateMachine.get_state(sm, "order:exp")
    assert {:ok, [entry]} = StateMachine.history(sm, "order:exp")
    assert entry.event == :expire
    assert entry.from_state == :pending
    assert entry.to_state == :cancelled
  end

  test "confirming before the TTL prevents auto-expiry" do
    {:ok, sm} = StateMachine.start_link(repo: @repo, pending_ttl_ms: 100)
    {:ok, :pending} = StateMachine.start(sm, "order:safe")
    {:ok, :confirmed} = StateMachine.transition(sm, "order:safe", :confirm)

    Process.sleep(200)

    # Expiry check fires but the entity is no longer pending, so it is a no-op.
    assert {:ok, :confirmed} = StateMachine.get_state(sm, "order:safe")
    assert {:ok, [%{event: :confirm}]} = StateMachine.history(sm, "order:safe")
  end

  test "manual :expire from :pending is a valid transition", %{sm: sm} do
    {:ok, :pending} = StateMachine.start(sm, "order:m")
    assert {:ok, :cancelled} = StateMachine.transition(sm, "order:m", :expire)
  end

  test "auto-expiry survives restart and re-hydrates as cancelled" do
    {:ok, sm} = StateMachine.start_link(repo: @repo, pending_ttl_ms: 50)
    {:ok, :pending} = StateMachine.start(sm, "order:rehy")
    Process.sleep(180)
    {:ok, :cancelled} = StateMachine.get_state(sm, "order:rehy")

    GenServer.stop(sm)
    {:ok, sm2} = StateMachine.start_link(repo: @repo)
    assert {:ok, :cancelled} = StateMachine.start(sm2, "order:rehy")
  end

  # ---------------------------------------------------------------------------
  # History
  # ---------------------------------------------------------------------------

  test "history/2 records every transition in order", %{sm: sm} do
    {:ok, :pending} = StateMachine.start(sm, "order:1")
    {:ok, :confirmed} = StateMachine.transition(sm, "order:1", :confirm)
    {:ok, :shipped} = StateMachine.transition(sm, "order:1", :ship)

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

  # ---------------------------------------------------------------------------
  # Concurrency
  # ---------------------------------------------------------------------------

  test "concurrent transitions on the same entity serialize", %{sm: sm} do
    {:ok, :pending} = StateMachine.start(sm, "order:cc")

    tasks =
      for _ <- 1..20 do
        Task.async(fn -> StateMachine.transition(sm, "order:cc", :confirm) end)
      end

    results = Task.await_many(tasks)
    oks = Enum.filter(results, &match?({:ok, :confirmed}, &1))
    errors = Enum.filter(results, &match?({:error, :invalid_transition}, &1))

    assert length(oks) == 1
    assert length(errors) == 19
  end

  # ---------------------------------------------------------------------------
  # Test-support helpers
  # ---------------------------------------------------------------------------

  defp ensure_repo_started do
    unless Process.whereis(@repo) do
      if is_nil(Application.get_env(:state_machine, @repo)) do
        # pid AND integer: unique_integer is unique only within one BEAM, and the
        # validator runs one BEAM per task in parallel (same rule as
        # EvalTask.Runner.uniq_suffix/0).
        db =
          Path.join(
            System.tmp_dir!(),
            "sm_#{System.pid()}_#{System.unique_integer([:positive])}.sqlite3"
          )

        Application.put_env(:state_machine, @repo,
          database: db,
          pool: Ecto.Adapters.SQL.Sandbox,
          pool_size: 20
        )
      end

      {:ok, _pid} = @repo.start_link()
    end

    Ecto.Adapters.SQL.Sandbox.mode(@repo, :manual)
    :ok
  end

  defp ensure_migrated do
    Ecto.Adapters.SQL.Sandbox.unboxed_run(@repo, fn ->
      Ecto.Migrator.run(@repo, [{1, Repo.Migrations.CreateEntityTransitions}], :up,
        all: true,
        log: false
      )
    end)

    :ok
  rescue
    _error -> :ok
  end

  test "transition/3 reports a db error and leaves the in-memory state untouched" do
    {:module, failing_repo, _, _} =
      defmodule FailingRepo do
        def one(_query), do: nil
        def all(_query), do: []
        def insert(_struct), do: {:error, :disk_full}
      end

    {:ok, sm} = StateMachine.start_link(repo: failing_repo)
    {:ok, :pending} = StateMachine.start(sm, "order:dbfail")

    assert {:error, {:db_error, :disk_full}} =
             StateMachine.transition(sm, "order:dbfail", :confirm)

    assert {:ok, :pending} = StateMachine.get_state(sm, "order:dbfail")
  end

  test "cancel from :pending yields :cancelled and records the transition", %{sm: sm} do
    {:ok, :pending} = StateMachine.start(sm, "order:cancel-p")

    assert {:ok, :cancelled} = StateMachine.transition(sm, "order:cancel-p", :cancel)
    assert {:ok, :cancelled} = StateMachine.get_state(sm, "order:cancel-p")

    assert {:ok, [%{event: :cancel, from_state: :pending, to_state: :cancelled}]} =
             StateMachine.history(sm, "order:cancel-p")
  end

  test "cancel from :confirmed yields :cancelled and records the transition", %{sm: sm} do
    {:ok, :pending} = StateMachine.start(sm, "order:cancel-c")
    {:ok, :confirmed} = StateMachine.transition(sm, "order:cancel-c", :confirm)

    assert {:ok, :cancelled} = StateMachine.transition(sm, "order:cancel-c", :cancel)
    assert {:ok, :cancelled} = StateMachine.get_state(sm, "order:cancel-c")

    assert {:ok, [_confirm, %{event: :cancel, from_state: :confirmed, to_state: :cancelled}]} =
             StateMachine.history(sm, "order:cancel-c")
  end

  test "an invalid transition writes no row to the history", %{sm: sm} do
    {:ok, :pending} = StateMachine.start(sm, "order:novoid")

    assert {:error, :invalid_transition} = StateMachine.transition(sm, "order:novoid", :deliver)
    assert {:ok, []} = StateMachine.history(sm, "order:novoid")
  end

  test "the :name option registers the server so the API can be driven by name" do
    {:ok, pid} = StateMachine.start_link(repo: @repo, name: :sm_named_server)

    assert Process.whereis(:sm_named_server) == pid
    assert {:ok, :pending} = StateMachine.start(:sm_named_server, "order:named")
    assert {:ok, :confirmed} = StateMachine.transition(:sm_named_server, "order:named", :confirm)
    assert {:ok, :confirmed} = StateMachine.get_state(:sm_named_server, "order:named")
  end

  test "history entries expose atom lifecycle values and a DateTime inserted_at", %{sm: sm} do
    {:ok, :pending} = StateMachine.start(sm, "order:dt")
    {:ok, :confirmed} = StateMachine.transition(sm, "order:dt", :confirm)

    assert {:ok, [entry]} = StateMachine.history(sm, "order:dt")
    assert %DateTime{} = entry.inserted_at
    assert is_atom(entry.event)
    assert is_atom(entry.from_state)
    assert is_atom(entry.to_state)
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
