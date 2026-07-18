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
defmodule RadixTrie do
  @enforce_keys [:root, :size]
  defstruct [:root, :size]

  # ---------------------------------------------------------------------------
  # Construction
  # ---------------------------------------------------------------------------

  def new, do: %__MODULE__{root: new_node(), size: 0}

  defp new_node, do: %{edges: %{}, terminal: false}

  # ---------------------------------------------------------------------------
  # Insert
  # ---------------------------------------------------------------------------

  def insert(%__MODULE__{root: root, size: size}, word) when is_binary(word) do
    {new_root, added} = do_insert(root, word)
    %__MODULE__{root: new_root, size: size + added}
  end

  defp do_insert(node, "") do
    if node.terminal, do: {node, 0}, else: {%{node | terminal: true}, 1}
  end

  defp do_insert(node, word) do
    key = String.first(word)

    case Map.fetch(node.edges, key) do
      :error ->
        leaf = %{edges: %{}, terminal: true}
        edge = %{label: word, child: leaf}
        {%{node | edges: Map.put(node.edges, key, edge)}, 1}

      {:ok, %{label: label, child: child} = edge} ->
        cp = common_prefix(label, word)
        plen = String.length(cp)
        llen = String.length(label)
        wlen = String.length(word)

        cond do
          # whole edge label is consumed — descend into the child
          plen == llen ->
            {new_child, added} = do_insert(child, drop(word, plen))
            new_edge = %{edge | child: new_child}
            {%{node | edges: Map.put(node.edges, key, new_edge)}, added}

          # the word is a proper prefix of the edge label — split the edge
          plen == wlen ->
            suffix = drop(label, plen)
            old_edge = %{label: suffix, child: child}
            mid = %{edges: %{String.first(suffix) => old_edge}, terminal: true}
            {%{node | edges: Map.put(node.edges, key, %{label: cp, child: mid})}, 1}

          # partial overlap — branch into a fresh intermediate node
          true ->
            label_suffix = drop(label, plen)
            word_suffix = drop(word, plen)
            old_edge = %{label: label_suffix, child: child}
            new_leaf = %{edges: %{}, terminal: true}
            new_edge = %{label: word_suffix, child: new_leaf}

            mid = %{
              edges: %{
                String.first(label_suffix) => old_edge,
                String.first(word_suffix) => new_edge
              },
              terminal: false
            }

            {%{node | edges: Map.put(node.edges, key, %{label: cp, child: mid})}, 1}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Membership
  # ---------------------------------------------------------------------------

  def member?(%__MODULE__{root: root}, word) when is_binary(word), do: do_member(root, word)

  defp do_member(node, ""), do: node.terminal

  defp do_member(node, word) do
    key = String.first(word)

    case Map.fetch(node.edges, key) do
      :error ->
        false

      {:ok, %{label: label, child: child}} ->
        if String.starts_with?(word, label) do
          do_member(child, drop(word, String.length(label)))
        else
          false
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Prefix search
  # ---------------------------------------------------------------------------

  def search(%__MODULE__{root: root}, prefix) when is_binary(prefix) do
    case locate(root, prefix, "") do
      :nomatch -> []
      {node, path} -> collect(node, path) |> Enum.sort()
    end
  end

  # Walk down consuming `prefix`; `acc` is the actual path string to `node`.
  defp locate(node, "", acc), do: {node, acc}

  defp locate(node, prefix, acc) do
    key = String.first(prefix)

    case Map.fetch(node.edges, key) do
      :error ->
        :nomatch

      {:ok, %{label: label, child: child}} ->
        cond do
          String.starts_with?(prefix, label) ->
            locate(child, drop(prefix, String.length(label)), acc <> label)

          String.starts_with?(label, prefix) ->
            {child, acc <> label}

          true ->
            :nomatch
        end
    end
  end

  defp collect(node, path) do
    base = if node.terminal, do: [path], else: []

    Enum.reduce(node.edges, base, fn {_key, %{label: label, child: child}}, acc ->
      collect(child, path <> label) ++ acc
    end)
  end

  # ---------------------------------------------------------------------------
  # Delete
  # ---------------------------------------------------------------------------

  def delete(%__MODULE__{root: root, size: size} = trie, word) when is_binary(word) do
    case do_delete(root, word) do
      :notfound -> trie
      {new_root, :ok} -> %__MODULE__{root: new_root, size: size - 1}
    end
  end

  defp do_delete(node, "") do
    if node.terminal, do: {%{node | terminal: false}, :ok}, else: :notfound
  end

  defp do_delete(node, word) do
    key = String.first(word)

    case Map.fetch(node.edges, key) do
      :error ->
        :notfound

      {:ok, %{label: label, child: child} = edge} ->
        if String.starts_with?(word, label) do
          case do_delete(child, drop(word, String.length(label))) do
            :notfound -> :notfound
            {new_child, :ok} -> {cleanup_edge(node, key, edge, new_child), :ok}
          end
        else
          :notfound
        end
    end
  end

  defp cleanup_edge(node, key, edge, new_child) do
    cond do
      # dead-end leaf — prune it
      not new_child.terminal and map_size(new_child.edges) == 0 ->
        %{node | edges: Map.delete(node.edges, key)}

      # single non-terminal child — re-merge the labels
      not new_child.terminal and map_size(new_child.edges) == 1 ->
        [{_k, grand}] = Map.to_list(new_child.edges)
        merged = %{edge | label: edge.label <> grand.label, child: grand.child}
        %{node | edges: Map.put(node.edges, key, merged)}

      true ->
        %{node | edges: Map.put(node.edges, key, %{edge | child: new_child})}
    end
  end

  # ---------------------------------------------------------------------------
  # Size / Words / Node count
  # ---------------------------------------------------------------------------

  def size(%__MODULE__{size: size}), do: size

  def words(%__MODULE__{root: root}), do: collect(root, "") |> Enum.sort()

  def node_count(%__MODULE__{root: root}), do: count_nodes(root)

  defp count_nodes(node) do
    Enum.reduce(node.edges, 1, fn {_key, %{child: child}}, acc -> acc + count_nodes(child) end)
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp drop(str, n), do: String.slice(str, n, String.length(str))

  defp common_prefix(a, b), do: do_common(String.graphemes(a), String.graphemes(b), [])

  defp do_common([x | xs], [x | ys], acc), do: do_common(xs, ys, [x | acc])
  defp do_common(_, _, acc), do: acc |> Enum.reverse() |> Enum.join()
end
```
