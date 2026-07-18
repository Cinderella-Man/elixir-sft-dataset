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
defmodule Trie do
  @enforce_keys [:root, :size]
  defstruct [:root, :size]

  # ---------------------------------------------------------------------------
  # Construction
  # ---------------------------------------------------------------------------

  def new, do: %__MODULE__{root: new_node(), size: 0}

  defp new_node, do: %{children: %{}, end_of_word: false}

  # ---------------------------------------------------------------------------
  # Insert
  # ---------------------------------------------------------------------------

  def insert(%__MODULE__{root: root, size: size} = trie, word) when is_binary(word) do
    chars = String.graphemes(word)

    if word_exists?(root, chars) do
      trie
    else
      %__MODULE__{root: do_insert(root, chars), size: size + 1}
    end
  end

  defp do_insert(node, []) do
    %{node | end_of_word: true}
  end

  defp do_insert(node, [char | rest]) do
    child = Map.get(node.children, char, new_node())
    updated_child = do_insert(child, rest)
    %{node | children: Map.put(node.children, char, updated_child)}
  end

  # ---------------------------------------------------------------------------
  # Membership
  # ---------------------------------------------------------------------------

  def member?(%__MODULE__{root: root}, word) when is_binary(word) do
    word_exists?(root, String.graphemes(word))
  end

  defp word_exists?(_node, _chars)

  defp word_exists?(%{end_of_word: eow}, []), do: eow

  defp word_exists?(%{children: children}, [char | rest]) do
    case Map.fetch(children, char) do
      {:ok, child} -> word_exists?(child, rest)
      :error -> false
    end
  end

  # ---------------------------------------------------------------------------
  # Prefix search
  # ---------------------------------------------------------------------------

  def search(%__MODULE__{root: root}, prefix) when is_binary(prefix) do
    chars = String.graphemes(prefix)

    case descend(root, chars) do
      nil -> []
      node -> collect(node, prefix) |> Enum.sort()
    end
  end

  # Walk down the trie following `chars`, returning the subtree or nil.
  defp descend(node, []), do: node

  defp descend(%{children: children}, [char | rest]) do
    case Map.fetch(children, char) do
      {:ok, child} -> descend(child, rest)
      :error -> nil
    end
  end

  # Depth-first collection of all complete words beneath `node`.
  defp collect(%{end_of_word: eow, children: children}, acc) do
    current = if eow, do: [acc], else: []

    children
    |> Enum.reduce(current, fn {char, child}, words ->
      collect(child, acc <> char) ++ words
    end)
  end

  # ---------------------------------------------------------------------------
  # Delete
  # ---------------------------------------------------------------------------

  def delete(%__MODULE__{root: root, size: size} = trie, word) when is_binary(word) do
    chars = String.graphemes(word)

    if word_exists?(root, chars) do
      %__MODULE__{root: do_delete(root, chars), size: size - 1}
    else
      trie
    end
  end

  defp do_delete(node, []) do
    %{node | end_of_word: false}
  end

  defp do_delete(node, [char | rest]) do
    child = Map.fetch!(node.children, char)
    updated_child = do_delete(child, rest)

    if not updated_child.end_of_word and map_size(updated_child.children) == 0 do
      # The child is now a dead-end leaf — prune it.
      %{node | children: Map.delete(node.children, char)}
    else
      %{node | children: Map.put(node.children, char, updated_child)}
    end
  end

  # ---------------------------------------------------------------------------
  # Size / Words
  # ---------------------------------------------------------------------------

  def size(%__MODULE__{size: size}), do: size

  def words(%__MODULE__{root: root}) do
    collect(root, "") |> Enum.sort()
  end
end
```
