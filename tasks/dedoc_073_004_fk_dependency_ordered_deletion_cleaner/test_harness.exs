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
  end

  setup do
    start_supervised!(FakeRepo)
    FakeRepo.reset()
    :ok
  end

  defp deleted_tables do
    Enum.flat_map(FakeRepo.calls(), fn
      {:query, "DELETE FROM " <> table} -> [table]
      _ -> []
    end)
  end

  test "start/2 issues no SQL" do
    assert {:ok, :deletion} =
             DBCleaner.start(:deletion,
               repo: FakeRepo,
               tables: [{"comments", ["posts"]}, {"posts", ["users"]}, "users"]
             )

    assert FakeRepo.calls() == []
  end

  test "clean/0 deletes children before the parents they reference" do
    DBCleaner.start(:deletion,
      repo: FakeRepo,
      tables: [{"comments", ["posts"]}, {"posts", ["users"]}, "users"]
    )

    assert :ok = DBCleaner.clean()
    assert deleted_tables() == ["comments", "posts", "users"]
  end

  test "deletion_order/1 orders children first, parents last" do
    spec = %{"comments" => ["posts"], "posts" => ["users"], "users" => []}
    assert {:ok, ["comments", "posts", "users"]} = DBCleaner.deletion_order(spec)
  end

  test "deletion_order/1 breaks ties deterministically by name" do
    spec = %{"zebra" => [], "alpha" => [], "mango" => []}
    assert {:ok, ["alpha", "mango", "zebra"]} = DBCleaner.deletion_order(spec)
  end

  test "deletion_order/1 ignores dependencies on unlisted tables" do
    spec = %{"posts" => ["users"], "comments" => ["posts", "authors"]}
    assert {:ok, ["comments", "posts"]} = DBCleaner.deletion_order(spec)
  end

  test "deletion_order/1 reports a cycle" do
    spec = %{"a" => ["b"], "b" => ["a"]}
    assert {:error, {:cycle, ["a", "b"]}} = DBCleaner.deletion_order(spec)
  end

  test "clean/0 with a cyclic spec issues no queries and returns an error" do
    DBCleaner.start(:deletion,
      repo: FakeRepo,
      tables: [{"a", ["b"]}, {"b", ["a"]}]
    )

    assert {:error, {:cycle, ["a", "b"]}} = DBCleaner.clean()
    assert deleted_tables() == []
  end

  test "clean/0 without a prior start is a safe no-op" do
    assert :ok = DBCleaner.clean()
    assert FakeRepo.calls() == []
  end

  test "start/2 raises on an invalid table identifier" do
    assert_raise ArgumentError, fn ->
      DBCleaner.start(:deletion, repo: FakeRepo, tables: ["users; DROP TABLE x"])
    end
  end

  test "plain string entries with no dependencies delete in sorted order" do
    DBCleaner.start(:deletion, repo: FakeRepo, tables: ["orders", "carts", "items"])
    DBCleaner.clean()
    assert deleted_tables() == ["carts", "items", "orders"]
  end
end
