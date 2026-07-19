# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `on_cycle?` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me a self-contained Elixir context module `Catalog` that performs **dependency-ordered bulk creation** of catalog entries into an in-memory store, with per-item, index-aware result reporting.

This is a variation on a plain bulk-create endpoint: here the items in a single batch may reference **other items in the same batch** as their parent, so the module must resolve those references, create entries in a valid topological order, detect cycles, and — in partial mode — cascade-skip the dependents of any item that fails.

**Store**
- Back the module with a named `Agent` started via `Catalog.start_link/0` (registered under the module name).
- Provide `Catalog.all/0` (list of stored items), `Catalog.count/0`, and `Catalog.get/1` (by id).
- Each stored item is a map `%{id: integer, name: String.t(), ref: String.t() | nil, parent_id: integer | nil}` with an auto-incrementing integer `id`.

**Input shape**
- Each attribute map may contain: `"name"` (required, 1–100 chars), `"ref"` (optional string — a temporary in-batch identifier; a `ref` value declared by more than one item marks **every** one of those declaring items as a `:duplicate_ref` error), and `"parent"` (optional string — a reference to another item's `"ref"` in the same batch; `nil`/absent means a root item).

**`Catalog.bulk_create(list_of_attrs, opts \\ [])`**
Compute per-item validity and dependency status, then:

- Every result carries the zero-based position index from the original input. Result tuples are:
  - `{index, :ok, item}` — created (or `{index, :ok, :valid}` when validated-but-not-stored in an all-or-nothing rollback),
  - `{index, :error, reason}` — where `reason` is `{:validation, errors_map}`, `:duplicate_ref`, `:unknown_parent`, or `:cycle`,
  - `{index, :skipped, ancestor_index}` — a valid item skipped because an ancestor was bad/skipped.
- **Default (all-or-nothing):** if *any* item is bad (invalid, duplicate ref, unknown parent) or involved in a cycle — meaning not every item is creatable — roll everything back (store nothing) and return `{:error, results}`. If every item is creatable, create them all in dependency order (parents before children, resolving `parent_id` to the real created id) and return `{:ok, results}`.
- **`partial: true`:** create every creatable item in dependency order; bad items are reported as errors and their transitive dependents are reported as `:skipped` (with the index of the nearest bad/skipped ancestor). Return `{:ok, results}`.

A dependent whose parent `ref` is *declared but duplicated* still points at a known ref, so in partial mode it is reported as `:skipped` (ancestor being one of the declaring indices), not `:unknown_parent`.

Cycle detection must mark exactly the items **on** a cycle as `:cycle`; items merely downstream of a cycle are `:skipped`. Use only Elixir/OTP standard library — no external dependencies.

## Additional interface contract

- In a `{:validation, errors_map}` reason, `errors_map` is keyed by the
  **string** field name (not an atom), with each value a list of
  human-readable message strings — e.g. a blank name yields
  `%{"name" => ["can't be blank"]}`.

## The module with `on_cycle?` missing

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
    # TODO
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

Give me only the complete implementation of `on_cycle?` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
