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
defmodule WildcardTrie do
  @enforce_keys [:root, :size]
  defstruct [:root, :size]

  @wildcard "."

  # ---------------------------------------------------------------------------
  # Construction
  # ---------------------------------------------------------------------------

  def new, do: %__MODULE__{root: new_node(), size: 0}

  defp new_node, do: %{children: %{}, terminal: false}

  # ---------------------------------------------------------------------------
  # Insert
  # ---------------------------------------------------------------------------

  def insert(%__MODULE__{root: root, size: size} = trie, word) when is_binary(word) do
    chars = String.graphemes(word)

    if exact?(root, chars) do
      trie
    else
      %__MODULE__{root: do_insert(root, chars), size: size + 1}
    end
  end

  defp do_insert(node, []), do: %{node | terminal: true}

  defp do_insert(node, [char | rest]) do
    child = Map.get(node.children, char, new_node())
    %{node | children: Map.put(node.children, char, do_insert(child, rest))}
  end

  # ---------------------------------------------------------------------------
  # Exact membership
  # ---------------------------------------------------------------------------

  def member?(%__MODULE__{root: root}, word) when is_binary(word) do
    exact?(root, String.graphemes(word))
  end

  defp exact?(%{terminal: terminal}, []), do: terminal

  defp exact?(%{children: children}, [char | rest]) do
    case Map.fetch(children, char) do
      {:ok, child} -> exact?(child, rest)
      :error -> false
    end
  end

  # ---------------------------------------------------------------------------
  # Wildcard matching
  # ---------------------------------------------------------------------------

  def matches?(%__MODULE__{root: root}, pattern) when is_binary(pattern) do
    do_matches?(root, String.graphemes(pattern))
  end

  defp do_matches?(%{terminal: terminal}, []), do: terminal

  defp do_matches?(%{children: children}, [@wildcard | rest]) do
    Enum.any?(children, fn {_char, child} -> do_matches?(child, rest) end)
  end

  defp do_matches?(%{children: children}, [char | rest]) do
    case Map.fetch(children, char) do
      {:ok, child} -> do_matches?(child, rest)
      :error -> false
    end
  end

  def matching(%__MODULE__{root: root}, pattern) when is_binary(pattern) do
    root |> do_matching(String.graphemes(pattern), "") |> Enum.sort()
  end

  defp do_matching(%{terminal: terminal}, [], acc) do
    if terminal, do: [acc], else: []
  end

  defp do_matching(%{children: children}, [@wildcard | rest], acc) do
    Enum.flat_map(children, fn {char, child} -> do_matching(child, rest, acc <> char) end)
  end

  defp do_matching(%{children: children}, [char | rest], acc) do
    case Map.fetch(children, char) do
      {:ok, child} -> do_matching(child, rest, acc <> char)
      :error -> []
    end
  end

  # ---------------------------------------------------------------------------
  # Delete
  # ---------------------------------------------------------------------------

  def delete(%__MODULE__{root: root, size: size} = trie, word) when is_binary(word) do
    chars = String.graphemes(word)

    if exact?(root, chars) do
      %__MODULE__{root: do_delete(root, chars), size: size - 1}
    else
      trie
    end
  end

  defp do_delete(node, []), do: %{node | terminal: false}

  defp do_delete(node, [char | rest]) do
    child = Map.fetch!(node.children, char)
    new_child = do_delete(child, rest)

    if not new_child.terminal and map_size(new_child.children) == 0 do
      %{node | children: Map.delete(node.children, char)}
    else
      %{node | children: Map.put(node.children, char, new_child)}
    end
  end

  # ---------------------------------------------------------------------------
  # Size / Words
  # ---------------------------------------------------------------------------

  def size(%__MODULE__{size: size}), do: size

  def words(%__MODULE__{root: root}), do: root |> collect("") |> Enum.sort()

  defp collect(%{terminal: terminal, children: children}, acc) do
    base = if terminal, do: [acc], else: []

    Enum.reduce(children, base, fn {char, child}, words ->
      collect(child, acc <> char) ++ words
    end)
  end
end
```
