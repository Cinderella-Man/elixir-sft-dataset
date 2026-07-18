# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule Catalog do
  def start_link(_ \\ []) do
    Agent.start_link(fn -> %{items: %{}, next_id: 1} end, name: __MODULE__)
  end

  def all, do: Agent.get(__MODULE__, fn %{items: items} -> Map.values(items) end)

  def count, do: Agent.get(__MODULE__, fn %{items: items} -> map_size(items) end)

  def get(id), do: Agent.get(__MODULE__, fn %{items: items} -> Map.get(items, id) end)

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
