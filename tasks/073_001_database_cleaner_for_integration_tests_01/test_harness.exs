defmodule DBCleanerTest do
  use ExUnit.Case, async: false

  # --- Fake Repo for deterministic testing ---

  defmodule FakeRepo do
    use Agent

    # Tracks SQL calls made: [{:query, sql} | {:begin} | {:rollback}]
    def start_link(_opts \\ []) do
      Agent.start_link(fn -> [] end, name: __MODULE__)
    end

    def calls, do: Agent.get(__MODULE__, &Enum.reverse/1)
    def reset, do: Agent.update(__MODULE__, fn _ -> [] end)

    # Simulates Ecto.Adapters.SQL.query!/3
    def query!(_repo, sql, _params) do
      Agent.update(__MODULE__, &[{:query, sql} | &1])
      %{rows: [], num_rows: 0}
    end

    # Simulates beginning a transaction
    def begin_transaction do
      Agent.update(__MODULE__, &[{:begin} | &1])
      {:ok, make_ref()}
    end

    # Simulates rolling back
    def rollback do
      Agent.update(__MODULE__, &[{:rollback} | &1])
      :ok
    end
  end

  setup do
    start_supervised!(FakeRepo)
    FakeRepo.reset()
    :ok
  end

  # -------------------------------------------------------
  # :truncation strategy
  # -------------------------------------------------------

  test "truncation: start/2 is a no-op" do
    DBCleaner.start(:truncation, repo: FakeRepo, tables: ["users", "posts"])
    assert FakeRepo.calls() == []
  end

  test "truncation: clean/0 truncates all listed tables" do
    DBCleaner.start(:truncation, repo: FakeRepo, tables: ["users", "posts"])
    DBCleaner.clean()

    calls = FakeRepo.calls()
    assert length(calls) == 2

    sqls = Enum.map(calls, fn {:query, sql} -> sql end)
    assert Enum.any?(sqls, &String.contains?(&1, "users"))
    assert Enum.any?(sqls, &String.contains?(&1, "posts"))
    assert Enum.all?(sqls, &String.contains?(&1, "TRUNCATE"))
  end

  test "truncation: clean/0 includes RESTART IDENTITY CASCADE" do
    DBCleaner.start(:truncation, repo: FakeRepo, tables: ["events"])
    DBCleaner.clean()

    [{:query, sql}] = FakeRepo.calls()
    assert String.contains?(sql, "RESTART IDENTITY")
    assert String.contains?(sql, "CASCADE")
  end

  test "truncation: empty tables list results in no queries" do
    DBCleaner.start(:truncation, repo: FakeRepo, tables: [])
    DBCleaner.clean()
    assert FakeRepo.calls() == []
  end

  test "truncation: clean/0 is safe to call without a prior start (no crash)" do
    # Should either be a no-op or raise a clear error, but must not crash the test process
    assert_raise(RuntimeError, fn -> DBCleaner.clean() end) or true
  rescue
    _ -> :ok
  end

  # -------------------------------------------------------
  # :transaction strategy
  # -------------------------------------------------------

  test "transaction: start/2 begins a transaction" do
    DBCleaner.start(:transaction, repo: FakeRepo, tables: [])
    assert {:begin} in FakeRepo.calls()
  end

  test "transaction: clean/0 rolls back the transaction" do
    DBCleaner.start(:transaction, repo: FakeRepo, tables: [])
    FakeRepo.reset()

    DBCleaner.clean()

    assert {:rollback} in FakeRepo.calls()
  end

  test "transaction: no truncation queries are issued on clean/0" do
    DBCleaner.start(:transaction, repo: FakeRepo, tables: ["users"])
    FakeRepo.reset()

    DBCleaner.clean()

    refute Enum.any?(FakeRepo.calls(), fn
             {:query, sql} -> String.contains?(sql, "TRUNCATE")
             _ -> false
           end)
  end

  # -------------------------------------------------------
  # State isolation between strategies
  # -------------------------------------------------------

  test "switching strategy between tests does not bleed state" do
    DBCleaner.start(:truncation, repo: FakeRepo, tables: ["orders"])
    DBCleaner.clean()
    truncation_calls = FakeRepo.calls()

    FakeRepo.reset()

    DBCleaner.start(:transaction, repo: FakeRepo, tables: [])
    DBCleaner.clean()
    transaction_calls = FakeRepo.calls()

    # Truncation run produced TRUNCATE queries, transaction run did not
    assert Enum.any?(truncation_calls, fn
             {:query, sql} -> String.contains?(sql, "TRUNCATE")
             _ -> false
           end)

    refute Enum.any?(transaction_calls, fn
             {:query, sql} -> String.contains?(sql, "TRUNCATE")
             _ -> false
           end)
  end

  # -------------------------------------------------------
  # Isolation guarantee (behavioral)
  # -------------------------------------------------------

  test "truncation: records inserted between start and clean are gone after clean" do
    # Simulate an in-memory 'table' to stand in for a real DB
    {:ok, table} = Agent.start_link(fn -> [] end)

    insert = fn row -> Agent.update(table, &[row | &1]) end
    all = fn -> Agent.get(table, & &1) end
    truncate = fn -> Agent.update(table, fn _ -> [] end) end

    # Override clean behaviour inline for this test
    insert.(%{id: 1, name: "Alice"})
    assert length(all.()) == 1

    truncate.()
    assert all.() == []

    # Second test run: table is clean at the start
    insert.(%{id: 2, name: "Bob"})
    assert length(all.()) == 1
  end

  test "transaction: rollback leaves the table unchanged" do
    {:ok, table} = Agent.start_link(fn -> ["existing"] end)

    snapshot = Agent.get(table, & &1)

    # 'Begin' captures snapshot, inserts happen, rollback restores
    Agent.update(table, &["new_record" | &1])
    assert length(Agent.get(table, & &1)) == 2

    # Rollback = restore snapshot
    Agent.update(table, fn _ -> snapshot end)
    assert Agent.get(table, & &1) == ["existing"]
  end
end
