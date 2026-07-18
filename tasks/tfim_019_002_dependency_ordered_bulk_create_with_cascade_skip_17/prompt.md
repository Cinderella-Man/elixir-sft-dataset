# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule Catalog do
  @moduledoc """
  Dependency-ordered bulk creation into an in-memory store.

  Items in a batch may reference other items (by a temporary `"ref"`) as their
  `"parent"`. Creation happens in topological order; cycles and unknown
  references are detected. Every result carries the original zero-based index.
  """

  @typedoc "A stored catalog item with an auto-incrementing integer id."
  @type item :: %{
          id: pos_integer(),
          name: String.t(),
          ref: String.t() | nil,
          parent_id: integer() | nil
        }

  @typedoc "Raw attribute map from the caller."
  @type attrs :: %{optional(String.t()) => term()}

  @typedoc "Why an item could not be created."
  @type reason :: {:validation, map()} | :duplicate_ref | :unknown_parent | :cycle

  @typedoc "A per-item, index-aware result tuple."
  @type result ::
          {non_neg_integer(), :ok, item() | :valid}
          | {non_neg_integer(), :error, reason()}
          | {non_neg_integer(), :skipped, non_neg_integer()}

  @doc """
  Start the backing `Agent`, registered under this module's name.
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(_ \\ []) do
    Agent.start_link(fn -> %{items: %{}, next_id: 1} end, name: __MODULE__)
  end

  @doc "Return every stored item."
  @spec all() :: [item()]
  def all, do: Agent.get(__MODULE__, fn %{items: items} -> Map.values(items) end)

  @doc "Return the number of stored items."
  @spec count() :: non_neg_integer()
  def count, do: Agent.get(__MODULE__, fn %{items: items} -> map_size(items) end)

  @doc "Fetch a stored item by id, or `nil` if it does not exist."
  @spec get(integer()) :: item() | nil
  def get(id), do: Agent.get(__MODULE__, fn %{items: items} -> Map.get(items, id) end)

  @doc """
  Bulk-create items with index-aware, dependency-aware result reporting.

  Modes:
    * default — all-or-nothing: any bad/cyclic item rolls back the whole batch.
    * `partial: true` — create creatable items; skip dependents of bad items.
  """
  @spec bulk_create([attrs()], keyword()) :: {:ok, [result()]} | {:error, [result()]}
  def bulk_create(list, opts \\ []) do
    partial? = Keyword.get(opts, :partial, false)
    n = length(list)
    indices = Enum.to_list(0..(n - 1)//1)
    attrs_by_index = list |> Enum.with_index() |> Map.new(fn {a, i} -> {i, a} end)

    # Reference index and duplicate detection. A ref declared more than once is
    # a `:duplicate_ref` error for each declaring item, but the ref itself is
    # still *known*: dependents point at the first declaring index so they are
    # reported as `:skipped` rather than `:unknown_parent`.
    refs = for i <- indices, r = attrs_by_index[i]["ref"], is_binary(r), do: {r, i}
    ref_groups = Enum.group_by(refs, fn {r, _} -> r end, fn {_, i} -> i end)

    dup_ref_indices =
      for {_r, is} <- ref_groups, length(is) > 1, i <- is, into: MapSet.new(), do: i

    ref_index = for {r, is} <- ref_groups, into: %{}, do: {r, Enum.min(is)}

    # Parent resolution.
    {parent_of, unknown_parent} =
      Enum.reduce(indices, {%{}, MapSet.new()}, fn i, {po, up} ->
        case attrs_by_index[i]["parent"] do
          nil ->
            {Map.put(po, i, nil), up}

          p when is_binary(p) ->
            case Map.fetch(ref_index, p) do
              {:ok, pi} when pi != i -> {Map.put(po, i, pi), up}
              {:ok, _self} -> {Map.put(po, i, i), up}
              :error -> {Map.put(po, i, nil), MapSet.put(up, i)}
            end

          _ ->
            {Map.put(po, i, nil), MapSet.put(up, i)}
        end
      end)

    # Per-item validation.
    val_errors = Map.new(indices, fn i -> {i, validate(attrs_by_index[i])} end)

    # Cycle membership (only nodes actually on a cycle).
    cyclic =
      for i <- indices, on_cycle?(i, parent_of), into: MapSet.new(), do: i

    bad_reason =
      Map.new(indices, fn i ->
        reason =
          cond do
            val_errors[i] != nil -> {:validation, val_errors[i]}
            MapSet.member?(dup_ref_indices, i) -> :duplicate_ref
            MapSet.member?(unknown_parent, i) -> :unknown_parent
            MapSet.member?(cyclic, i) -> :cycle
            true -> nil
          end

        {i, reason}
      end)

    status = Map.new(indices, fn i -> {i, status_of(i, parent_of, bad_reason)} end)

    creatable = for i <- indices, status[i] == :ok, into: MapSet.new(), do: i

    cond do
      partial? ->
        items = create_all(creatable, parent_of, attrs_by_index)
        {:ok, build_results(indices, status, items)}

      MapSet.size(creatable) == n ->
        items = create_all(creatable, parent_of, attrs_by_index)
        {:ok, build_results(indices, status, items)}

      true ->
        {:error, build_results(indices, status, %{})}
    end
  end

  # -- validation ----------------------------------------------------------

  defp validate(attrs) do
    name = attrs["name"]

    errors =
      cond do
        not is_binary(name) or name == "" -> %{"name" => ["can't be blank"]}
        String.length(name) > 100 -> %{"name" => ["should be at most 100 character(s)"]}
        true -> %{}
      end

    if map_size(errors) == 0, do: nil, else: errors
  end

  # -- cycle detection (functional graph: each node has <= 1 parent) --------

  defp on_cycle?(x, parent_of) do
    follow(parent_of[x], parent_of, x, MapSet.new([x]))
  end

  defp follow(nil, _po, _target, _seen), do: false

  defp follow(node, po, target, seen) do
    cond do
      node == target -> true
      MapSet.member?(seen, node) -> false
      true -> follow(po[node], po, target, MapSet.put(seen, node))
    end
  end

  # -- status resolution ----------------------------------------------------

  defp status_of(i, parent_of, bad_reason) do
    case bad_reason[i] do
      nil ->
        case parent_of[i] do
          nil ->
            :ok

          p ->
            case status_of(p, parent_of, bad_reason) do
              :ok -> :ok
              _ -> {:skipped, p}
            end
        end

      reason ->
        {:bad, reason}
    end
  end

  # -- topological creation -------------------------------------------------

  defp create_all(creatable, parent_of, attrs_by_index) do
    order = topo(creatable, parent_of)

    {_ids, items} =
      Enum.reduce(order, {%{}, %{}}, fn i, {ids, items} ->
        parent_id =
          case parent_of[i] do
            nil -> nil
            p -> Map.get(ids, p)
          end

        a = attrs_by_index[i]
        item = insert(a["name"], a["ref"], parent_id)
        {Map.put(ids, i, item.id), Map.put(items, i, item)}
      end)

    items
  end

  defp topo(creatable, parent_of), do: do_topo(creatable, parent_of, MapSet.new(), [])

  defp do_topo(creatable, parent_of, placed, acc) do
    ready =
      creatable
      |> MapSet.to_list()
      |> Enum.reject(&MapSet.member?(placed, &1))
      |> Enum.filter(fn i ->
        case parent_of[i] do
          nil -> true
          p -> MapSet.member?(placed, p)
        end
      end)
      |> Enum.sort()

    case ready do
      [] ->
        Enum.reverse(acc)

      _ ->
        new_placed = Enum.reduce(ready, placed, &MapSet.put(&2, &1))
        do_topo(creatable, parent_of, new_placed, Enum.reverse(ready) ++ acc)
    end
  end

  defp insert(name, ref, parent_id) do
    Agent.get_and_update(__MODULE__, fn %{items: items, next_id: id} = st ->
      item = %{id: id, name: name, ref: ref, parent_id: parent_id}
      {item, %{st | items: Map.put(items, id, item), next_id: id + 1}}
    end)
  end

  # -- result assembly ------------------------------------------------------

  defp build_results(indices, status, items) do
    Enum.map(indices, fn i ->
      case status[i] do
        :ok ->
          case Map.fetch(items, i) do
            {:ok, item} -> {i, :ok, item}
            :error -> {i, :ok, :valid}
          end

        {:bad, reason} ->
          {i, :error, reason}

        {:skipped, anc} ->
          {i, :skipped, anc}
      end
    end)
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
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
    # TODO
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
end
```
