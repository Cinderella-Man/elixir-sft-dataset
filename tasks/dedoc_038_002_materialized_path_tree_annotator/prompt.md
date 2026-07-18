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
defmodule TreePaths do
  def build(items, opts \\ [])

  def build([], _opts), do: {:ok, []}

  def build(items, opts) when is_list(items) do
    orphan_strategy = Keyword.get(opts, :orphan_strategy, :discard)

    {id_to_node, ordered_ids} = index_items(items)

    case detect_duplicate_ids(items) do
      {:error, _} = err ->
        err

      :ok ->
        children_map = build_children_map(items)
        known_ids = MapSet.new(ordered_ids)

        case detect_cycle(ordered_ids, children_map) do
          {:error, _} = err ->
            err

          :ok ->
            root_ids =
              Enum.filter(ordered_ids, fn id ->
                pid = Map.fetch!(id_to_node, id).parent_id

                cond do
                  is_nil(pid) -> true
                  not MapSet.member?(known_ids, pid) -> orphan_strategy == :raise_to_root
                  true -> false
                end
              end)

            nodes =
              Enum.flat_map(root_ids, fn id ->
                flatten(id, id_to_node, children_map, 0, [])
              end)

            {:ok, nodes}
        end
    end
  end

  def subtree(nodes, id) when is_list(nodes) do
    if Enum.any?(nodes, &(&1.id == id)) do
      {:ok, Enum.filter(nodes, fn node -> id in node.path end)}
    else
      {:error, :not_found}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp flatten(id, id_to_node, children_map, depth, ancestor_path) do
    node = Map.fetch!(id_to_node, id)
    path = ancestor_path ++ [id]

    annotated =
      node
      |> Map.put(:depth, depth)
      |> Map.put(:path, path)

    child_ids = Map.get(children_map, id, [])

    descendants =
      Enum.flat_map(child_ids, fn child_id ->
        flatten(child_id, id_to_node, children_map, depth + 1, path)
      end)

    [annotated | descendants]
  end

  defp index_items(items) do
    {map, ids} =
      Enum.reduce(items, {%{}, []}, fn item, {map, ids} ->
        id = Map.fetch!(item, :id)
        {Map.put(map, id, item), [id | ids]}
      end)

    {map, Enum.reverse(ids)}
  end

  defp detect_duplicate_ids(items) do
    ids = Enum.map(items, & &1.id)
    unique = Enum.uniq(ids)

    if length(ids) == length(unique) do
      :ok
    else
      dupes =
        ids
        |> Enum.frequencies()
        |> Enum.filter(fn {_id, count} -> count > 1 end)
        |> Enum.map(fn {id, _} -> id end)

      {:error, {:duplicate_ids, dupes}}
    end
  end

  defp build_children_map(items) do
    Enum.reduce(items, %{}, fn item, acc ->
      pid = item.parent_id

      if is_nil(pid) do
        acc
      else
        Map.update(acc, pid, [item.id], fn existing -> existing ++ [item.id] end)
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Cycle detection — iterative DFS (white/grey/black colouring)
  # ---------------------------------------------------------------------------

  defp detect_cycle(all_ids, children_map) do
    initial_colors = Map.new(all_ids, fn id -> {id, :white} end)

    Enum.reduce_while(all_ids, {:ok, initial_colors}, fn id, {:ok, colors} ->
      if Map.get(colors, id) == :white do
        case dfs(id, children_map, colors, []) do
          {:ok, new_colors} -> {:cont, {:ok, new_colors}}
          {:error, _} = err -> {:halt, err}
        end
      else
        {:cont, {:ok, colors}}
      end
    end)
    |> case do
      {:ok, _colors} -> :ok
      {:error, _} = err -> err
    end
  end

  defp dfs(id, children_map, colors, stack) do
    colors = Map.put(colors, id, :grey)
    stack = [id | stack]
    child_ids = Map.get(children_map, id, [])

    result =
      Enum.reduce_while(child_ids, {:ok, colors}, fn child_id, {:ok, acc_colors} ->
        case Map.get(acc_colors, child_id) do
          :grey ->
            cycle = extract_cycle(child_id, [child_id | stack])
            {:halt, {:error, {:cycle_detected, cycle}}}

          :white ->
            case dfs(child_id, children_map, acc_colors, stack) do
              {:ok, new_colors} -> {:cont, {:ok, new_colors}}
              {:error, _} = err -> {:halt, err}
            end

          :black ->
            {:cont, {:ok, acc_colors}}

          nil ->
            {:cont, {:ok, acc_colors}}
        end
      end)

    case result do
      {:ok, colors} -> {:ok, Map.put(colors, id, :black)}
      {:error, _} = err -> err
    end
  end

  defp extract_cycle(cycle_root, path) do
    path
    |> Enum.reverse()
    |> Enum.drop_while(fn id -> id != cycle_root end)
    |> Enum.uniq()
    |> case do
      [] -> [cycle_root]
      slice -> slice
    end
  end
end
```
