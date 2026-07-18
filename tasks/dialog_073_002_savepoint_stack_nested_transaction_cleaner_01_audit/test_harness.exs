defmodule DBCleanerTest do
  use ExUnit.Case, async: false

  defmodule FakeRepo do
    use Agent

    def start_link(_opts \\ []) do
      Agent.start_link(fn -> [] end, name: __MODULE__)
    end

    def calls, do: Agent.get(__MODULE__, &Enum.reverse/1)
    def reset, do: Agent.update(__MODULE__, fn _ -> [] end)

    def query!(_repo, sql, _params) do
      Agent.update(__MODULE__, &[{:query, sql} | &1])
      %{rows: [], num_rows: 0}
    end

    def begin_transaction do
      Agent.update(__MODULE__, &[{:begin} | &1])
      {:ok, make_ref()}
    end

    def rollback do
      Agent.update(__MODULE__, &[{:rollback} | &1])
      :ok
    end
  end

  # A repo whose operations raise on demand. The failure set is kept in the
  # calling process's dictionary, and DBCleaner invokes the repo from that very
  # process, so each test can arm failures independently.
  defmodule FlakyRepo do
    @fail_key {__MODULE__, :fail_on}

    def fail_on(ops), do: Process.put(@fail_key, ops)

    def begin_transaction do
      maybe_raise(:begin)
      {:ok, make_ref()}
    end

    def query!(_repo, _sql, _params) do
      maybe_raise(:query)
      %{rows: [], num_rows: 0}
    end

    def rollback do
      maybe_raise(:rollback)
      :ok
    end

    defp maybe_raise(op) do
      if op in Process.get(@fail_key, []) do
        raise RuntimeError, "#{op} boom"
      end

      :ok
    end
  end

  setup do
    start_supervised!(FakeRepo)
    FakeRepo.reset()
    :ok
  end

  defp sqls do
    Enum.flat_map(FakeRepo.calls(), fn
      {:query, sql} -> [sql]
      _ -> []
    end)
  end

  test "start/2 begins an outer transaction and empty stack" do
    assert {:ok, :savepoint} = DBCleaner.start(:savepoint, repo: FakeRepo)
    assert {:begin} in FakeRepo.calls()
    assert DBCleaner.active_savepoints() == []
  end

  test "savepoint/1 issues SAVEPOINT and tracks the stack" do
    DBCleaner.start(:savepoint, repo: FakeRepo)
    assert {:ok, "a"} = DBCleaner.savepoint("a")
    assert {:ok, "b"} = DBCleaner.savepoint("b")

    assert DBCleaner.active_savepoints() == ["a", "b"]
    assert Enum.any?(sqls(), &(&1 == "SAVEPOINT a"))
    assert Enum.any?(sqls(), &(&1 == "SAVEPOINT b"))
  end

  test "rollback_to/1 issues ROLLBACK TO and trims newer savepoints" do
    DBCleaner.start(:savepoint, repo: FakeRepo)
    DBCleaner.savepoint("a")
    DBCleaner.savepoint("b")
    DBCleaner.savepoint("c")

    assert {:ok, "b"} = DBCleaner.rollback_to("b")
    assert DBCleaner.active_savepoints() == ["a", "b"]
    assert Enum.any?(sqls(), &(&1 == "ROLLBACK TO SAVEPOINT b"))
  end

  test "rollback_to/1 on an unknown savepoint returns an error" do
    DBCleaner.start(:savepoint, repo: FakeRepo)
    DBCleaner.savepoint("a")
    assert {:error, {:no_such_savepoint, "z"}} = DBCleaner.rollback_to("z")
  end

  test "release/1 releases the savepoint and any created after it" do
    DBCleaner.start(:savepoint, repo: FakeRepo)
    DBCleaner.savepoint("a")
    DBCleaner.savepoint("b")
    DBCleaner.savepoint("c")

    assert {:ok, "b"} = DBCleaner.release("b")
    assert DBCleaner.active_savepoints() == ["a"]
    assert Enum.any?(sqls(), &(&1 == "RELEASE SAVEPOINT b"))
  end

  test "savepoint/1 before start returns :not_started" do
    assert {:error, :not_started} = DBCleaner.savepoint("a")
  end

  test "savepoint/1 rejects invalid identifiers without issuing SQL" do
    DBCleaner.start(:savepoint, repo: FakeRepo)
    FakeRepo.reset()

    assert {:error, {:invalid_name, "a; DROP TABLE users"}} =
             DBCleaner.savepoint("a; DROP TABLE users")

    assert sqls() == []
  end

  test "clean/0 rolls back the outer transaction and clears state" do
    DBCleaner.start(:savepoint, repo: FakeRepo)
    DBCleaner.savepoint("a")
    FakeRepo.reset()

    assert :ok = DBCleaner.clean()
    assert {:rollback} in FakeRepo.calls()
    assert DBCleaner.active_savepoints() == []
  end

  test "clean/0 without a prior start is a safe no-op" do
    assert :ok = DBCleaner.clean()
    assert FakeRepo.calls() == []
  end

  test "state does not bleed across sequential start/clean cycles" do
    DBCleaner.start(:savepoint, repo: FakeRepo)
    DBCleaner.savepoint("a")
    DBCleaner.clean()

    DBCleaner.start(:savepoint, repo: FakeRepo)
    assert DBCleaner.active_savepoints() == []
  end

  test "release/1 on an unknown savepoint errors without issuing SQL" do
    DBCleaner.start(:savepoint, repo: FakeRepo)
    DBCleaner.savepoint("a")
    FakeRepo.reset()

    assert {:error, {:no_such_savepoint, "z"}} = DBCleaner.release("z")
    assert sqls() == []
    assert DBCleaner.active_savepoints() == ["a"]
  end

  test "rollback_to/1 keeps the target reusable and discards newer savepoints" do
    DBCleaner.start(:savepoint, repo: FakeRepo)
    DBCleaner.savepoint("a")
    DBCleaner.savepoint("b")
    DBCleaner.savepoint("c")

    assert {:ok, "b"} = DBCleaner.rollback_to("b")
    assert {:error, {:no_such_savepoint, "c"}} = DBCleaner.rollback_to("c")
    assert {:ok, "b"} = DBCleaner.rollback_to("b")
    assert DBCleaner.active_savepoints() == ["a", "b"]
  end

  test "savepoint/1 accepts underscore-led identifiers and rejects leading digits" do
    DBCleaner.start(:savepoint, repo: FakeRepo)

    assert {:ok, "_sp1"} = DBCleaner.savepoint("_sp1")
    assert {:error, {:invalid_name, "1sp"}} = DBCleaner.savepoint("1sp")
    assert {:error, {:invalid_name, ""}} = DBCleaner.savepoint("")
    assert DBCleaner.active_savepoints() == ["_sp1"]
    assert Enum.any?(sqls(), &(&1 == "SAVEPOINT _sp1"))
  end

  test "clean/0 clears state so a second clean and later calls are no-ops" do
    DBCleaner.start(:savepoint, repo: FakeRepo)
    DBCleaner.savepoint("a")
    DBCleaner.clean()
    FakeRepo.reset()

    assert :ok = DBCleaner.clean()
    assert FakeRepo.calls() == []
    assert {:error, :not_started} = DBCleaner.savepoint("a")
    assert DBCleaner.active_savepoints() == []
  end

  test "release/1 with duplicate names releases only the most recent one" do
    DBCleaner.start(:savepoint, repo: FakeRepo)
    DBCleaner.savepoint("a")
    DBCleaner.savepoint("b")
    DBCleaner.savepoint("a")

    assert {:ok, "a"} = DBCleaner.release("a")
    assert DBCleaner.active_savepoints() == ["a", "b"]
    assert Enum.any?(sqls(), &(&1 == "RELEASE SAVEPOINT a"))
  end

  test "start/2 with an unknown strategy returns an error and starts nothing" do
    assert {:error, message} = DBCleaner.start(:transaction, repo: FakeRepo)
    assert is_binary(message)
    assert message =~ "unknown strategy"
    assert FakeRepo.calls() == []
    assert DBCleaner.active_savepoints() == []
    assert {:error, :not_started} = DBCleaner.savepoint("a")
  end

  test "start/2 surfaces a failing begin_transaction as an error and leaves no state" do
    FlakyRepo.fail_on([:begin])

    assert {:error, "begin boom"} = DBCleaner.start(:savepoint, repo: FlakyRepo)
    assert DBCleaner.active_savepoints() == []
    assert {:error, :not_started} = DBCleaner.savepoint("a")
  end

  test "start/2 requires :repo and rejects a non-atom repo" do
    assert_raise ArgumentError, fn -> DBCleaner.start(:savepoint, []) end
    assert_raise ArgumentError, fn -> DBCleaner.start(:savepoint, repo: "MyApp.Repo") end
    assert DBCleaner.active_savepoints() == []
  end

  test "savepoint/1 rejects non-string names" do
    DBCleaner.start(:savepoint, repo: FakeRepo)
    FakeRepo.reset()

    assert {:error, {:invalid_name, :a}} = DBCleaner.savepoint(:a)
    assert {:error, {:invalid_name, 1}} = DBCleaner.savepoint(1)
    assert sqls() == []
    assert DBCleaner.active_savepoints() == []
  end

  test "savepoint/1 surfaces a failing query and leaves the stack untouched" do
    assert {:ok, :savepoint} = DBCleaner.start(:savepoint, repo: FlakyRepo)
    assert {:ok, "a"} = DBCleaner.savepoint("a")

    FlakyRepo.fail_on([:query])

    assert {:error, "query boom"} = DBCleaner.savepoint("b")
    assert DBCleaner.active_savepoints() == ["a"]
  end

  test "rollback_to/1 before start returns :not_started" do
    assert {:error, :not_started} = DBCleaner.rollback_to("a")
  end

  test "rollback_to/1 surfaces a failing query and leaves the stack untouched" do
    assert {:ok, :savepoint} = DBCleaner.start(:savepoint, repo: FlakyRepo)
    DBCleaner.savepoint("a")
    DBCleaner.savepoint("b")

    FlakyRepo.fail_on([:query])

    assert {:error, "query boom"} = DBCleaner.rollback_to("a")
    assert DBCleaner.active_savepoints() == ["a", "b"]
  end

  test "release/1 before start returns :not_started" do
    assert {:error, :not_started} = DBCleaner.release("a")
  end

  test "release/1 surfaces a failing query and leaves the stack untouched" do
    assert {:ok, :savepoint} = DBCleaner.start(:savepoint, repo: FlakyRepo)
    DBCleaner.savepoint("a")
    DBCleaner.savepoint("b")

    FlakyRepo.fail_on([:query])

    assert {:error, "query boom"} = DBCleaner.release("a")
    assert DBCleaner.active_savepoints() == ["a", "b"]
  end

  test "clean/0 surfaces a failing rollback but still clears state" do
    assert {:ok, :savepoint} = DBCleaner.start(:savepoint, repo: FlakyRepo)
    DBCleaner.savepoint("a")

    FlakyRepo.fail_on([:rollback])

    assert {:error, "rollback boom"} = DBCleaner.clean()
    assert DBCleaner.active_savepoints() == []
    assert {:error, :not_started} = DBCleaner.savepoint("a")
    assert :ok = DBCleaner.clean()
  end
end
