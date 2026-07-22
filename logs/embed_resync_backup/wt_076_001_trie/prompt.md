# Write tests for this module

Below is a completed Elixir module and the original specification it was built to
satisfy. Write a comprehensive ExUnit test harness that verifies a correct
implementation of this module.

Requirements for the harness:
- Define a module `<Module>Test` that does `use ExUnit.Case, async: false`.
- Do NOT call `ExUnit.start()` — the evaluator starts ExUnit itself.
- Make it self-contained: any fakes, clock Agents, or helpers are defined inline.
- Cover the full public API and the important edge cases described in the spec.
- It must compile with ZERO warnings (prefix unused variables with `_`; match float
  zero as `+0.0`/`-0.0`).
- Give me the complete harness in a single file.

## Original specification

Build me a Trie (prefix tree) data structure Elixir module called `Trie`. I want a pure functional implementation — no GenServer or ETS, just a struct and functions that return new tries.

Here's the API I need:

- `Trie.new()` returns an empty trie
- `Trie.insert(trie, word)` inserts a word (string) and returns the updated trie
- `Trie.member?(trie, word)` returns true if the exact word was inserted, false otherwise. The word "car" being present should NOT make `member?("ca")` return true unless "ca" was also inserted separately.
- `Trie.search(trie, prefix)` returns a sorted list of all words in the trie that start with the given prefix. If the prefix itself was inserted as a word, include it too.
- `Trie.delete(trie, word)` removes a word and returns the updated trie. Deleting "car" should not affect "card" if "card" is also in the trie — only the end-of-word marker for "car" should be removed, shared prefix nodes stay.
- `Trie.size(trie)` returns the count of words currently in the trie
- `Trie.words(trie)` returns a sorted list of all words in the trie

Implementation-wise I'd expect the trie to be a nested map structure where each node is a map of `%{children: %{char => node}, end_of_word: boolean}` or similar. The key thing is it needs to be purely functional — every operation returns a new trie without mutating the original.

No external dependencies. Single file with the `Trie` module.

## Module under test

```elixir
defmodule Trie do
  @moduledoc """
  A pure functional prefix tree (trie) backed by nested maps.

  Every operation returns a new trie — nothing is mutated.

  ## Node structure

      %{children: %{char => node}, end_of_word: boolean}

  The top-level trie is simply the root node wrapped in a struct that also
  tracks the total word count so `size/1` is O(1).
  """

  @enforce_keys [:root, :size]
  defstruct [:root, :size]

  @type trie_node :: %{children: %{String.t() => trie_node}, end_of_word: boolean}
  @type t :: %__MODULE__{root: trie_node, size: non_neg_integer}

  # ---------------------------------------------------------------------------
  # Construction
  # ---------------------------------------------------------------------------

  @doc "Returns an empty trie."
  @spec new() :: t
  def new, do: %__MODULE__{root: new_node(), size: 0}

  defp new_node, do: %{children: %{}, end_of_word: false}

  # ---------------------------------------------------------------------------
  # Insert
  # ---------------------------------------------------------------------------

  @doc "Inserts `word` into the trie. Returns the updated trie."
  @spec insert(t, String.t()) :: t
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

  @doc """
  Returns `true` if `word` was explicitly inserted, `false` otherwise.

  A prefix that was never inserted on its own will return `false`.
  """
  @spec member?(t, String.t()) :: boolean
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

  @doc """
  Returns a sorted list of every word that starts with `prefix`.

  If `prefix` itself was inserted as a word it is included in the result.
  """
  @spec search(t, String.t()) :: [String.t()]
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

  @doc """
  Removes `word` from the trie. Returns the updated trie.

  Only the end-of-word marker is cleared; shared prefix nodes that are still
  needed by other words are left intact. Orphaned branch nodes are pruned.

  Deleting a word that isn't present is a no-op.
  """
  @spec delete(t, String.t()) :: t
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

  @doc "Returns the number of words in the trie. O(1)."
  @spec size(t) :: non_neg_integer
  def size(%__MODULE__{size: size}), do: size

  @doc "Returns a sorted list of every word in the trie."
  @spec words(t) :: [String.t()]
  def words(%__MODULE__{root: root}) do
    collect(root, "") |> Enum.sort()
  end
end
```
