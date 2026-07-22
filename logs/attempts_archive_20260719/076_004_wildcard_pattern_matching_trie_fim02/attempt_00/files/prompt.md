Implement the private `do_matching/3` function — the recursive worker behind
`WildcardTrie.matching/2`. It walks the trie guided by the remaining pattern
graphemes and returns a list of the fully-spelled stored words that match,
building each word up in an accumulator string.

It takes three arguments: the current `node`, the list of remaining pattern
graphemes, and `acc` (the prefix spelled out so far while descending from the
root). It returns a list of matched words (strings). Write it as three clauses:

1. **Pattern exhausted (`[]`)** — you have consumed the whole pattern. Return
   `[acc]` if the current node is `terminal` (a word ends here), otherwise `[]`.
2. **Head is the wildcard (`.`)** — the `.` matches any single character, so
   branch into *every* child: `flat_map` over `node.children`, recursing into
   each child with the rest of the pattern and `acc <> char`.
3. **Head is a literal character** — look it up in `node.children`. If a child
   exists, recurse into it with the rest of the pattern and `acc <> char`;
   otherwise there is no match down this path, so return `[]`.

Because a `.` only ever consumes exactly one grapheme and the base case requires
the pattern to be fully consumed, this naturally matches only words of the same
length as the pattern. The `@wildcard` module attribute holds `"."`.

```elixir
defmodule WildcardTrie do
  @moduledoc """
  A pure functional prefix tree that supports wildcard pattern search.

  `matches?/2` and `matching/2` interpret a `.` in the query as a wildcard for
  exactly one character; `member?/2` is a strict literal lookup. A pattern only
  matches words of the same length. Every operation returns a new trie —
  nothing is mutated.

  ## Node structure

      %{children: %{char => node}, terminal: boolean}

  The struct tracks the word count so `size/1` is O(1).
  """

  @enforce_keys [:root, :size]
  defstruct [:root, :size]

  @wildcard "."

  @type node_t :: %{children: %{String.t() => node_t}, terminal: boolean}
  @type t :: %__MODULE__{root: node_t, size: non_neg_integer}

  # ---------------------------------------------------------------------------
  # Construction
  # ---------------------------------------------------------------------------

  @doc "Returns an empty trie."
  @spec new() :: t
  def new, do: %__MODULE__{root: new_node(), size: 0}

  defp new_node, do: %{children: %{}, terminal: false}

  # ---------------------------------------------------------------------------
  # Insert
  # ---------------------------------------------------------------------------

  @doc "Inserts `word` into the trie. Returns the updated trie."
  @spec insert(t, String.t()) :: t
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

  @doc "Returns `true` only if the exact literal `word` was inserted."
  @spec member?(t, String.t()) :: boolean
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

  @doc "Returns `true` if any stored word matches `pattern` (`.` = any char)."
  @spec matches?(t, String.t()) :: boolean
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

  @doc "Returns a sorted list of every stored word matching `pattern`."
  @spec matching(t, String.t()) :: [String.t()]
  def matching(%__MODULE__{root: root}, pattern) when is_binary(pattern) do
    root |> do_matching(String.graphemes(pattern), "") |> Enum.sort()
  end

  defp do_matching(node, pattern_chars, acc) do
    # TODO
  end

  # ---------------------------------------------------------------------------
  # Delete
  # ---------------------------------------------------------------------------

  @doc "Removes the exact `word`. Deleting an absent word is a no-op."
  @spec delete(t, String.t()) :: t
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

  @doc "Returns the number of words in the trie. O(1)."
  @spec size(t) :: non_neg_integer
  def size(%__MODULE__{size: size}), do: size

  @doc "Returns a sorted list of every word in the trie."
  @spec words(t) :: [String.t()]
  def words(%__MODULE__{root: root}), do: root |> collect("") |> Enum.sort()

  defp collect(%{terminal: terminal, children: children}, acc) do
    base = if terminal, do: [acc], else: []

    Enum.reduce(children, base, fn {char, child}, words ->
      collect(child, acc <> char) ++ words
    end)
  end
end
```