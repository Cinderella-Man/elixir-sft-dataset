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
defmodule MutableDAG do
  defstruct vertices: MapSet.new(), out_edges: %{}, in_edges: %{}

  # ---------------------------------------------------------------------------
  # Construction / mutation
  # ---------------------------------------------------------------------------

  def new, do: %__MODULE__{}

  def add_vertex(%__MODULE__{} = dag, vertex) do
    if MapSet.member?(dag.vertices, vertex) do
      dag
    else
      %{
        dag
        | vertices: MapSet.put(dag.vertices, vertex),
          out_edges: Map.put_new(dag.out_edges, vertex, MapSet.new()),
          in_edges: Map.put_new(dag.in_edges, vertex, MapSet.new())
      }
    end
  end

  def add_edge(%__MODULE__{} = dag, from, to) do
    with :ok <- require_vertex(dag, from),
         :ok <- require_vertex(dag, to) do
      cond do
        from == to ->
          {:error, {:cycle, [from, from]}}

        true ->
          # Adding from->to closes a cycle iff `from` is already reachable
          # from `to`. reach_path returns [to, ..., from] when such a path
          # exists; prefixing `from` yields the full loop [from, to, ..., from].
          case reach_path(dag.out_edges, to, from) do
            nil ->
              new_dag = %{
                dag
                | out_edges: Map.update!(dag.out_edges, from, &MapSet.put(&1, to)),
                  in_edges: Map.update!(dag.in_edges, to, &MapSet.put(&1, from))
              }

              {:ok, new_dag}

            path ->
              {:error, {:cycle, [from | path]}}
          end
      end
    end
  end

  def remove_edge(%__MODULE__{} = dag, from, to) do
    if MapSet.member?(dag.vertices, from) and MapSet.member?(dag.vertices, to) do
      %{
        dag
        | out_edges: Map.update(dag.out_edges, from, MapSet.new(), &MapSet.delete(&1, to)),
          in_edges: Map.update(dag.in_edges, to, MapSet.new(), &MapSet.delete(&1, from))
      }
    else
      dag
    end
  end

  def remove_vertex(%__MODULE__{} = dag, vertex) do
    if MapSet.member?(dag.vertices, vertex) do
      successors = Map.get(dag.out_edges, vertex, MapSet.new())
      predecessors = Map.get(dag.in_edges, vertex, MapSet.new())

      in_edges =
        Enum.reduce(successors, dag.in_edges, fn s, acc ->
          Map.update(acc, s, MapSet.new(), &MapSet.delete(&1, vertex))
        end)

      out_edges =
        Enum.reduce(predecessors, dag.out_edges, fn p, acc ->
          Map.update(acc, p, MapSet.new(), &MapSet.delete(&1, vertex))
        end)

      %{
        dag
        | vertices: MapSet.delete(dag.vertices, vertex),
          out_edges: Map.delete(out_edges, vertex),
          in_edges: Map.delete(in_edges, vertex)
      }
    else
      dag
    end
  end

  # ---------------------------------------------------------------------------
  # Queries
  # ---------------------------------------------------------------------------

  def predecessors(%__MODULE__{} = dag, vertex) do
    dag.in_edges |> Map.get(vertex, MapSet.new()) |> MapSet.to_list()
  end

  def successors(%__MODULE__{} = dag, vertex) do
    dag.out_edges |> Map.get(vertex, MapSet.new()) |> MapSet.to_list()
  end

  def topological_layers(%__MODULE__{} = dag) do
    in_degree =
      Map.new(dag.vertices, fn v -> {v, MapSet.size(Map.fetch!(dag.in_edges, v))} end)

    {:ok, build_layers(in_degree, dag.out_edges, [])}
  end

  def topological_sort(%__MODULE__{} = dag) do
    {:ok, layers} = topological_layers(dag)
    {:ok, Enum.concat(layers)}
  end

  # ---------------------------------------------------------------------------
  # Internals
  # ---------------------------------------------------------------------------

  defp build_layers(in_degree, out_edges, acc) do
    if map_size(in_degree) == 0 do
      Enum.reverse(acc)
    else
      layer =
        in_degree
        |> Enum.filter(fn {_v, d} -> d == 0 end)
        |> Enum.map(&elem(&1, 0))
        |> Enum.sort()

      remaining = Map.drop(in_degree, layer)

      new_in_degree =
        Enum.reduce(layer, remaining, fn v, deg ->
          Enum.reduce(Map.get(out_edges, v, MapSet.new()), deg, fn s, d ->
            Map.update!(d, s, &(&1 - 1))
          end)
        end)

      build_layers(new_in_degree, out_edges, [layer | acc])
    end
  end

  defp require_vertex(dag, vertex) do
    if MapSet.member?(dag.vertices, vertex), do: :ok, else: {:error, :vertex_not_found}
  end

  # Returns a path [current, ..., target] following out_edges, or nil.
  defp reach_path(out_edges, current, target) do
    do_reach(out_edges, current, target, MapSet.new(), [])
  end

  defp do_reach(out_edges, current, target, visited, acc) do
    cond do
      current == target ->
        Enum.reverse([current | acc])

      MapSet.member?(visited, current) ->
        nil

      true ->
        visited = MapSet.put(visited, current)

        out_edges
        |> Map.get(current, MapSet.new())
        |> MapSet.to_list()
        |> Enum.sort()
        |> Enum.find_value(fn neighbor ->
          do_reach(out_edges, neighbor, target, visited, [current | acc])
        end)
    end
  end
end
```
