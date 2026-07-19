# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `weight` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Build me a **weighted autocomplete trie** in an Elixir module called `AutocompleteTrie`. This isn't just a set-membership trie — every stored word carries an accumulated frequency **weight**, and the headline feature is ranked prefix suggestions: given a prefix, return the top-K matching words ordered by weight.

Keep it purely functional — no GenServer, no ETS. Just a struct and functions that return new tries.

API I need:

- `AutocompleteTrie.new()` returns an empty trie.
- `AutocompleteTrie.insert(trie, word, weight \\ 1)` inserts `word` (a string) with the given positive integer `weight`. If the word is already present, the weight is **added** to its existing weight (frequency accumulation). Returns the updated trie. A non-positive or non-integer `weight` is rejected by a guard clause, so such a call raises `FunctionClauseError`.
- `AutocompleteTrie.weight(trie, word)` returns the accumulated weight of `word`, or `0` if it was never inserted.
- `AutocompleteTrie.member?(trie, word)` returns `true` if the exact word has a positive weight, `false` otherwise. A stored "car" must NOT make `member?("ca")` return `true`. `member?("")` is `false` unless the empty string was itself inserted.
- `AutocompleteTrie.suggest(trie, prefix, k)` returns up to `k` words that start with `prefix` (including `prefix` itself if it was inserted), ranked by **descending weight**, with ties broken **lexicographically ascending**. Returns a plain list of the word strings. A prefix that matches nothing returns `[]`. An empty prefix ranks every word in the trie. `k` is a non-negative integer; `suggest(_, _, 0)` returns `[]`, and a negative `k` is rejected by a guard clause, raising `FunctionClauseError`.
- `AutocompleteTrie.delete(trie, word)` removes `word` entirely (all of its weight) and returns the updated trie. Deleting "car" must not affect "card". Deleting an absent word — including a prefix that exists only as a path to longer words — is a no-op. After a delete, re-inserting the word starts its weight fresh rather than resurrecting the old weight.
- `AutocompleteTrie.size(trie)` returns the count of distinct words currently stored (O(1)).
- `AutocompleteTrie.words(trie)` returns a sorted list of all words.

Suggested node shape: `%{children: %{char => node}, weight: non_neg_integer}`, where a positive `weight` marks the end of a word. The struct should also track the distinct-word count so `size/1` is O(1). Every operation returns a new trie without mutating the original.

No external dependencies. Single file with the `AutocompleteTrie` module.

## The module with `weight` missing

```elixir
defmodule AutocompleteTrie do
  @moduledoc """
  A pure functional, frequency-weighted prefix tree for autocomplete.

  Every stored word carries an accumulated integer weight; `suggest/3` returns
  the top-K words for a prefix ranked by descending weight (ties broken
  lexicographically). Every operation returns a new trie — nothing is mutated.

  ## Node structure

      %{children: %{char => node}, weight: non_neg_integer}

  A positive `weight` marks the end of a word. The struct tracks the distinct
  word count so `size/1` is O(1).
  """

  @enforce_keys [:root, :size]
  defstruct [:root, :size]

  @type node_t :: %{children: %{String.t() => node_t}, weight: non_neg_integer}
  @type t :: %__MODULE__{root: node_t, size: non_neg_integer}

  # ---------------------------------------------------------------------------
  # Construction
  # ---------------------------------------------------------------------------

  @doc "Returns an empty trie."
  @spec new() :: t
  def new, do: %__MODULE__{root: new_node(), size: 0}

  defp new_node, do: %{children: %{}, weight: 0}

  # ---------------------------------------------------------------------------
  # Insert
  # ---------------------------------------------------------------------------

  @doc """
  Inserts `word` with `weight` (default 1). Re-inserting a word adds to its
  accumulated weight. Returns the updated trie.
  """
  @spec insert(t, String.t(), pos_integer) :: t
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
    # TODO
  end

  @doc "Returns `true` if the exact `word` has a positive weight."
  @spec member?(t, String.t()) :: boolean
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

  @doc """
  Returns up to `k` words starting with `prefix`, ranked by descending weight
  with lexicographic tie-breaking.
  """
  @spec suggest(t, String.t(), non_neg_integer) :: [String.t()]
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

  @doc "Removes `word` entirely. Deleting an absent word is a no-op."
  @spec delete(t, String.t()) :: t
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

  @doc "Returns the number of distinct words. O(1)."
  @spec size(t) :: non_neg_integer
  def size(%__MODULE__{size: size}), do: size

  @doc "Returns a sorted list of every word in the trie."
  @spec words(t) :: [String.t()]
  def words(%__MODULE__{root: root}) do
    root |> collect("") |> Enum.map(fn {word, _weight} -> word end) |> Enum.sort()
  end
end
```

Give me only the complete implementation of `weight` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
