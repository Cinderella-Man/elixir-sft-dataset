defmodule CatalogTest do
  use ExUnit.Case, async: false

  setup do
    case Process.whereis(Catalog) do
      nil -> :ok
      pid -> Agent.stop(pid)
    end

    {:ok, _pid} = Catalog.start_link()
    :ok
  end

  defp item(results, index) do
    {^index, :ok, item} = Enum.find(results, fn {i, _, _} -> i == index end)
    item
  end

  test "creates all items when every item is valid with no dependencies" do
    items = [%{"name" => "Alpha"}, %{"name" => "Beta"}, %{"name" => "Gamma"}]

    assert {:ok, results} = Catalog.bulk_create(items)
    assert length(results) == 3
    assert Catalog.count() == 3

    for {i, expected} <-
          Enum.with_index(["Alpha", "Beta", "Gamma"]) |> Enum.map(fn {n, i} -> {i, n} end) do
      it = item(results, i)
      assert it.name == expected
      assert is_integer(it.id)
      assert it.parent_id == nil
    end
  end

  test "all/0 returns exactly the stored items" do
    # Empty store first.
    assert Catalog.all() == []

    items = [%{"name" => "Alpha"}, %{"name" => "Beta"}, %{"name" => "Gamma"}]
    assert {:ok, results} = Catalog.bulk_create(items)

    stored = Catalog.all()
    assert is_list(stored)
    assert length(stored) == 3

    # all/0 must return the same item maps that were created.
    created_maps = Enum.map([0, 1, 2], &item(results, &1))
    assert Enum.sort_by(stored, & &1.id) == Enum.sort_by(created_maps, & &1.id)

    assert MapSet.new(stored, & &1.name) == MapSet.new(["Alpha", "Beta", "Gamma"])
    assert Enum.all?(stored, &is_map/1)

    # get/1 for every id returned by all/0 must round-trip.
    for it <- stored do
      assert Catalog.get(it.id) == it
    end
  end

  test "all/0 reflects rollback: stores nothing on all-or-nothing failure" do
    items = [%{"name" => "ok"}, %{"name" => ""}]
    assert {:error, _results} = Catalog.bulk_create(items)
    assert Catalog.all() == []
  end

  test "resolves an in-batch parent even when the child appears before the parent" do
    items = [
      %{"name" => "child", "parent" => "r"},
      %{"name" => "root", "ref" => "r"}
    ]

    assert {:ok, results} = Catalog.bulk_create(items)
    child = item(results, 0)
    root = item(results, 1)

    assert child.parent_id == root.id
    assert root.parent_id == nil
    assert Catalog.count() == 2
  end

  test "resolves a multi-level dependency chain" do
    items = [
      %{"name" => "a", "ref" => "a"},
      %{"name" => "b", "ref" => "b", "parent" => "a"},
      %{"name" => "c", "parent" => "b"}
    ]

    assert {:ok, results} = Catalog.bulk_create(items)
    a = item(results, 0)
    b = item(results, 1)
    c = item(results, 2)

    assert a.parent_id == nil
    assert b.parent_id == a.id
    assert c.parent_id == b.id
  end

  test "all-or-nothing rolls back everything when a single item is invalid" do
    items = [%{"name" => "ok"}, %{"name" => ""}, %{"name" => "also ok"}]

    assert {:error, results} = Catalog.bulk_create(items)
    assert Catalog.count() == 0

    assert {1, :error, {:validation, errs}} = Enum.find(results, fn {i, _, _} -> i == 1 end)
    assert Map.has_key?(errs, "name")

    # Valid items appear as validated-but-not-stored
    assert {0, :ok, :valid} = Enum.find(results, fn {i, _, _} -> i == 0 end)
  end

  test "all-or-nothing reports unknown parent references" do
    items = [%{"name" => "x", "parent" => "nope"}]

    assert {:error, results} = Catalog.bulk_create(items)
    assert Catalog.count() == 0
    assert {0, :error, :unknown_parent} = hd(results)
  end

  test "all-or-nothing detects cycles" do
    items = [
      %{"name" => "a", "ref" => "a", "parent" => "b"},
      %{"name" => "b", "ref" => "b", "parent" => "a"}
    ]

    assert {:error, results} = Catalog.bulk_create(items)
    assert Catalog.count() == 0
    assert {0, :error, :cycle} = Enum.find(results, fn {i, _, _} -> i == 0 end)
    assert {1, :error, :cycle} = Enum.find(results, fn {i, _, _} -> i == 1 end)
  end

  test "partial mode skips invalid items and their dependents but creates independents" do
    items = [
      %{"name" => "", "ref" => "bad"},
      %{"name" => "dependent", "parent" => "bad"},
      %{"name" => "independent"}
    ]

    assert {:ok, results} = Catalog.bulk_create(items, partial: true)
    assert Catalog.count() == 1

    # all/0 must contain exactly the one created item.
    assert [only] = Catalog.all()
    assert only.name == "independent"

    assert {0, :error, {:validation, _}} = Enum.find(results, fn {i, _, _} -> i == 0 end)
    assert {1, :skipped, 0} = Enum.find(results, fn {i, _, _} -> i == 1 end)
    assert {2, :ok, item} = Enum.find(results, fn {i, _, _} -> i == 2 end)
    assert item.name == "independent"
    assert only == item
  end

  test "partial mode still creates a valid dependent with the correct parent_id" do
    items = [
      %{"name" => "root", "ref" => "r"},
      %{"name" => "child", "parent" => "r"}
    ]

    assert {:ok, results} = Catalog.bulk_create(items, partial: true)
    root = item(results, 0)
    child = item(results, 1)
    assert child.parent_id == root.id
    assert Catalog.count() == 2

    assert MapSet.new(Catalog.all()) == MapSet.new([root, child])
  end

  test "empty batch succeeds and stores nothing" do
    assert {:ok, []} = Catalog.bulk_create([])
    assert Catalog.count() == 0
    assert Catalog.all() == []
  end

  test "all-or-nothing reports duplicate refs and rolls the batch back" do
    items = [
      %{"name" => "first", "ref" => "dup"},
      %{"name" => "second", "ref" => "dup"},
      %{"name" => "clean"}
    ]

    assert {:error, results} = Catalog.bulk_create(items)
    assert Catalog.count() == 0
    assert Catalog.all() == []

    assert {0, :error, :duplicate_ref} = Enum.find(results, fn {i, _, _} -> i == 0 end)
    assert {1, :error, :duplicate_ref} = Enum.find(results, fn {i, _, _} -> i == 1 end)
    assert {2, :ok, :valid} = Enum.find(results, fn {i, _, _} -> i == 2 end)
  end

  test "partial mode marks only cycle members as :cycle and downstream items as skipped" do
    items = [
      %{"name" => "a", "ref" => "a", "parent" => "b"},
      %{"name" => "b", "ref" => "b", "parent" => "a"},
      %{"name" => "downstream", "parent" => "a"},
      %{"name" => "free"}
    ]

    assert {:ok, results} = Catalog.bulk_create(items, partial: true)

    assert {0, :error, :cycle} = Enum.find(results, fn {i, _, _} -> i == 0 end)
    assert {1, :error, :cycle} = Enum.find(results, fn {i, _, _} -> i == 1 end)
    assert {2, :skipped, 0} = Enum.find(results, fn {i, _, _} -> i == 2 end)
    assert {3, :ok, created} = Enum.find(results, fn {i, _, _} -> i == 3 end)

    assert created.name == "free"
    assert created.parent_id == nil
    assert Catalog.count() == 1
    assert [^created] = Catalog.all()
  end

  test "partial mode skips the dependent of a duplicate-ref item instead of erroring it" do
    items = [
      %{"name" => "one", "ref" => "dup"},
      %{"name" => "two", "ref" => "dup"},
      %{"name" => "child", "parent" => "dup"}
    ]

    assert {:ok, results} = Catalog.bulk_create(items, partial: true)

    assert {0, :error, :duplicate_ref} = Enum.find(results, fn {i, _, _} -> i == 0 end)
    assert {1, :error, :duplicate_ref} = Enum.find(results, fn {i, _, _} -> i == 1 end)
    assert {2, :skipped, ancestor} = Enum.find(results, fn {i, _, _} -> i == 2 end)
    assert ancestor in [0, 1]
    assert Catalog.count() == 0
  end

  test "name of exactly 100 chars is valid while 101 chars is a validation error" do
    items = [
      %{"name" => String.duplicate("a", 100)},
      %{"name" => String.duplicate("b", 101)}
    ]

    assert {:ok, results} = Catalog.bulk_create(items, partial: true)

    ok = item(results, 0)
    assert String.length(ok.name) == 100

    assert {1, :error, {:validation, errs}} = Enum.find(results, fn {i, _, _} -> i == 1 end)
    assert Map.has_key?(errs, "name")
    assert Catalog.count() == 1
  end

  test "validation errors_map is keyed by string field with a list of message strings" do
    assert {:error, results} = Catalog.bulk_create([%{"name" => ""}])
    assert {0, :error, {:validation, errs}} = hd(results)

    assert errs == %{"name" => ["can't be blank"]}
    assert Enum.all?(Map.keys(errs), &is_binary/1)
    assert Enum.all?(errs["name"], &is_binary/1)
  end

  test "ids auto-increment across items and across successive batches" do
    assert {:ok, first} = Catalog.bulk_create([%{"name" => "one"}, %{"name" => "two"}])
    a = item(first, 0)
    b = item(first, 1)
    assert is_integer(a.id)
    assert b.id == a.id + 1

    assert {:ok, second} = Catalog.bulk_create([%{"name" => "three"}])
    c = item(second, 0)
    assert c.id == b.id + 1
    assert Catalog.get(c.id) == c
    assert Catalog.count() == 3
  end

  test "skipped ancestor is the nearest skipped ancestor, not the root invalid item" do
    # Chain: invalid@0 -> 1 -> 2 -> 3. Each skipped item must report its own
    # nearest bad/skipped ancestor, which for 2 and 3 is a *skipped* item.
    items = [
      %{"name" => "", "ref" => "bad"},
      %{"name" => "mid one", "ref" => "m1", "parent" => "bad"},
      %{"name" => "mid two", "ref" => "m2", "parent" => "m1"},
      %{"name" => "leaf", "parent" => "m2"}
    ]

    assert {:ok, results} = Catalog.bulk_create(items, partial: true)

    assert {0, :error, {:validation, _}} = Enum.find(results, fn {i, _, _} -> i == 0 end)
    assert {1, :skipped, 0} = Enum.find(results, fn {i, _, _} -> i == 1 end)
    assert {2, :skipped, 1} = Enum.find(results, fn {i, _, _} -> i == 2 end)
    assert {3, :skipped, 2} = Enum.find(results, fn {i, _, _} -> i == 3 end)

    assert Catalog.count() == 0
    assert Catalog.all() == []
  end

  test "skipped ancestor below a cycle is the nearest skipped item, not a cycle member" do
    # Cycle on 0 and 1; 2 hangs off the cycle and 3 hangs off 2, so 3's nearest
    # bad/skipped ancestor is the skipped item 2.
    items = [
      %{"name" => "a", "ref" => "a", "parent" => "b"},
      %{"name" => "b", "ref" => "b", "parent" => "a"},
      %{"name" => "below", "ref" => "below", "parent" => "a"},
      %{"name" => "further below", "parent" => "below"}
    ]

    assert {:ok, results} = Catalog.bulk_create(items, partial: true)

    assert {0, :error, :cycle} = Enum.find(results, fn {i, _, _} -> i == 0 end)
    assert {1, :error, :cycle} = Enum.find(results, fn {i, _, _} -> i == 1 end)
    assert {2, :skipped, 0} = Enum.find(results, fn {i, _, _} -> i == 2 end)
    assert {3, :skipped, 2} = Enum.find(results, fn {i, _, _} -> i == 3 end)

    assert Catalog.count() == 0
    assert Catalog.all() == []
  end

  test "skipped ancestor below a duplicate-ref item is the immediate skipped parent" do
    # 2 points at a duplicated-but-known ref, so it is skipped; 3 depends on 2
    # and must report 2 rather than either duplicate-ref declaring index.
    items = [
      %{"name" => "one", "ref" => "dup"},
      %{"name" => "two", "ref" => "dup"},
      %{"name" => "child", "ref" => "child", "parent" => "dup"},
      %{"name" => "grandchild", "parent" => "child"}
    ]

    assert {:ok, results} = Catalog.bulk_create(items, partial: true)

    assert {0, :error, :duplicate_ref} = Enum.find(results, fn {i, _, _} -> i == 0 end)
    assert {1, :error, :duplicate_ref} = Enum.find(results, fn {i, _, _} -> i == 1 end)
    assert {2, :skipped, ancestor} = Enum.find(results, fn {i, _, _} -> i == 2 end)
    assert ancestor in [0, 1]
    assert {3, :skipped, 2} = Enum.find(results, fn {i, _, _} -> i == 3 end)

    assert Catalog.count() == 0
    assert Catalog.all() == []
  end
end
