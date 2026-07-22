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

  test "release/1 on an unknown savepoint returns an error and keeps the stack" do
    DBCleaner.start(:savepoint, repo: FakeRepo)
    DBCleaner.savepoint("a")
    DBCleaner.savepoint("b")

    assert {:error, {:no_such_savepoint, "z"}} = DBCleaner.release("z")
    assert DBCleaner.active_savepoints() == ["a", "b"]
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
end
