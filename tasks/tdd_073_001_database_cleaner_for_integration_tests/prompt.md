# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
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
    DBCleaner.clean()
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

  # -------------------------------------------------------
  # Return values pinned by the prompt
  # -------------------------------------------------------

  test "clean/0 without a prior start/2 returns :ok" do
    assert DBCleaner.clean() == :ok
  end

  # -------------------------------------------------------
  # Return shapes of start/2 and clean/0 pinned by the prompt
  # -------------------------------------------------------

  defmodule BeginRaisesRepo do
    def begin_transaction do
      raise RuntimeError, "begin_transaction exploded"
    end
  end

  defmodule CleanRaisesRepo do
    def begin_transaction, do: {:ok, make_ref()}

    def rollback do
      raise RuntimeError, "rollback exploded"
    end

    def query!(_repo, _sql, _params) do
      raise RuntimeError, "query! exploded"
    end
  end

  test "transaction: start/2 returns {:ok, :transaction} on success" do
    assert DBCleaner.start(:transaction, repo: FakeRepo) == {:ok, :transaction}
  end

  test "truncation: start/2 returns {:ok, :truncation} on success" do
    assert DBCleaner.start(:truncation, repo: FakeRepo, tables: ["users"]) == {:ok, :truncation}
  end

  test "start/2 with an unknown strategy returns {:error, message} with a String message" do
    assert {:error, message} = DBCleaner.start(:bogus, repo: FakeRepo)
    assert is_binary(message)
  end

  test "transaction: a raise from begin_transaction/0 is rescued into {:error, message}" do
    assert {:error, message} = DBCleaner.start(:transaction, repo: BeginRaisesRepo)
    assert is_binary(message)
  end

  test "transaction: clean/0 returns :ok on success" do
    DBCleaner.start(:transaction, repo: FakeRepo)
    assert DBCleaner.clean() == :ok
  end

  test "truncation: clean/0 returns :ok on success" do
    DBCleaner.start(:truncation, repo: FakeRepo, tables: ["users"])
    assert DBCleaner.clean() == :ok
  end

  test "transaction: a raise from rollback/0 makes clean/0 return {:error, message}" do
    DBCleaner.start(:transaction, repo: CleanRaisesRepo)
    assert {:error, message} = DBCleaner.clean()
    assert is_binary(message)
  end

  test "truncation: a raise from query!/3 makes clean/0 return {:error, message}" do
    DBCleaner.start(:truncation, repo: CleanRaisesRepo, tables: ["users"])
    assert {:error, message} = DBCleaner.clean()
    assert is_binary(message)
  end

  test "a failed transaction start/2 still replaces prior truncation state (no TRUNCATE on clean)" do
    assert {:ok, :truncation} =
             DBCleaner.start(:truncation, repo: FakeRepo, tables: ["users"])

    assert {:error, message} = DBCleaner.start(:transaction, repo: BeginRaisesRepo)
    assert is_binary(message)

    FakeRepo.reset()
    DBCleaner.clean()

    refute Enum.any?(FakeRepo.calls(), fn
             {:query, sql} -> String.contains?(sql, "TRUNCATE")
             _ -> false
           end)
  end

  test "truncation: clean/0 emits the exact bare-identifier TRUNCATE statement per table" do
    DBCleaner.start(:truncation, repo: FakeRepo, tables: ["users", "posts"])
    DBCleaner.clean()

    assert FakeRepo.calls() == [
             {:query, "TRUNCATE users RESTART IDENTITY CASCADE"},
             {:query, "TRUNCATE posts RESTART IDENTITY CASCADE"}
           ]
  end

  test "start/2 replaces an uncleaned truncation registration with a transaction one" do
    assert {:ok, :truncation} =
             DBCleaner.start(:truncation, repo: FakeRepo, tables: ["orders"])

    assert {:ok, :transaction} = DBCleaner.start(:transaction, repo: FakeRepo)

    FakeRepo.reset()
    assert DBCleaner.clean() == :ok

    calls = FakeRepo.calls()
    assert {:rollback} in calls

    refute Enum.any?(calls, fn
             {:query, _sql} -> true
             _ -> false
           end)
  end

  test "transaction: clean/0 issues no query!/3 call at all even when tables were given" do
    DBCleaner.start(:transaction, repo: FakeRepo, tables: ["users", "posts"])
    FakeRepo.reset()

    assert DBCleaner.clean() == :ok

    assert FakeRepo.calls() == [{:rollback}]
  end

  test "truncation: a second clean/0 after cleanup issues no further TRUNCATE statements" do
    DBCleaner.start(:truncation, repo: FakeRepo, tables: ["users"])
    assert DBCleaner.clean() == :ok
    FakeRepo.reset()

    assert DBCleaner.clean() == :ok
    assert FakeRepo.calls() == []
  end

  test "truncation: query!/3 receives the repo module itself and empty params" do
    defmodule EchoRepo do
      def query!(repo, sql, params) do
        send(self(), {:echo_query, repo, sql, params})
        %{rows: [], num_rows: 0}
      end
    end

    DBCleaner.start(:truncation, repo: EchoRepo, tables: ["users"])
    assert DBCleaner.clean() == :ok

    assert_receive {:echo_query, EchoRepo, "TRUNCATE users RESTART IDENTITY CASCADE", []}, 100
    refute_receive {:echo_query, _, _, _}, 50
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
