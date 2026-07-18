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
defmodule AutocompleteTrie do
  @enforce_keys [:root, :size]
  defstruct [:root, :size]

  # ---------------------------------------------------------------------------
  # Construction
  # ---------------------------------------------------------------------------

  def new, do: %__MODULE__{root: new_node(), size: 0}

  defp new_node, do: %{children: %{}, weight: 0}

  # ---------------------------------------------------------------------------
  # Insert
  # ---------------------------------------------------------------------------

  def insert(%__MODULE__{root: root, size: size}, word, weight \\ 1)
      when is_binary(word) and is_integer(weight) and weight > 0 do
    {new_root, delta} = do_insert(root, String.graphemes(word), weight)
    %__MODULE__{root: new_root, size: size + delta}
  end

  defp do_insert(node, [], weight) do
    delta = if node.weight == 0, do: 1, else: 0
    {%{node | weight: node.weight + weight}, delta}
  end

  defp do_insert(node, [char | rest], weight) do
    child = Map.get(node.children, char, new_node())
    {new_child, delta} = do_insert(child, rest, weight)
    {%{node | children: Map.put(node.children, char, new_child)}, delta}
  end

  # ---------------------------------------------------------------------------
  # Weight / Membership
  # ---------------------------------------------------------------------------

  def weight(%__MODULE__{root: root}, word) when is_binary(word) do
    case descend(root, String.graphemes(word)) do
      nil -> 0
      node -> node.weight
    end
  end

  def member?(%__MODULE__{} = trie, word) when is_binary(word), do: weight(trie, word) > 0

  defp descend(node, []), do: node

  defp descend(node, [char | rest]) do
    case Map.fetch(node.children, char) do
      {:ok, child} -> descend(child, rest)
      :error -> nil
    end
  end

  # ---------------------------------------------------------------------------
  # Ranked suggestions
  # ---------------------------------------------------------------------------

  def suggest(%__MODULE__{root: root}, prefix, k)
      when is_binary(prefix) and is_integer(k) and k >= 0 do
    case descend(root, String.graphemes(prefix)) do
      nil ->
        []

      node ->
        node
        |> collect(prefix)
        |> Enum.sort_by(fn {word, weight} -> {-weight, word} end)
        |> Enum.take(k)
        |> Enum.map(fn {word, _weight} -> word end)
    end
  end

  defp collect(node, prefix) do
    base = if node.weight > 0, do: [{prefix, node.weight}], else: []

    Enum.reduce(node.children, base, fn {char, child}, acc ->
      collect(child, prefix <> char) ++ acc
    end)
  end

  # ---------------------------------------------------------------------------
  # Delete
  # ---------------------------------------------------------------------------

  def delete(%__MODULE__{root: root, size: size} = trie, word) when is_binary(word) do
    case do_delete(root, String.graphemes(word)) do
      :notfound -> trie
      {new_root, :ok} -> %__MODULE__{root: new_root, size: size - 1}
    end
  end

  defp do_delete(node, []) do
    if node.weight == 0, do: :notfound, else: {%{node | weight: 0}, :ok}
  end

  defp do_delete(node, [char | rest]) do
    case Map.fetch(node.children, char) do
      :error ->
        :notfound

      {:ok, child} ->
        case do_delete(child, rest) do
          :notfound ->
            :notfound

          {new_child, :ok} ->
            if new_child.weight == 0 and map_size(new_child.children) == 0 do
              {%{node | children: Map.delete(node.children, char)}, :ok}
            else
              {%{node | children: Map.put(node.children, char, new_child)}, :ok}
            end
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Size / Words
  # ---------------------------------------------------------------------------

  def size(%__MODULE__{size: size}), do: size

  def words(%__MODULE__{root: root}) do
    root |> collect("") |> Enum.map(fn {word, _weight} -> word end) |> Enum.sort()
  end
end
```
