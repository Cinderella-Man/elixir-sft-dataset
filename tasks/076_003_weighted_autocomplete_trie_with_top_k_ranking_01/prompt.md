Build me a **weighted autocomplete trie** in an Elixir module called `AutocompleteTrie`. This isn't just a set-membership trie — every stored word carries an accumulated frequency **weight**, and the headline feature is ranked prefix suggestions: given a prefix, return the top-K matching words ordered by weight.

Keep it purely functional — no GenServer, no ETS. Just a struct and functions that return new tries.

API I need:

- `AutocompleteTrie.new()` returns an empty trie.
- `AutocompleteTrie.insert(trie, word, weight \\ 1)` inserts `word` (a string) with the given positive integer `weight`. If the word is already present, the weight is **added** to its existing weight (frequency accumulation). Returns the updated trie.
- `AutocompleteTrie.weight(trie, word)` returns the accumulated weight of `word`, or `0` if it was never inserted.
- `AutocompleteTrie.member?(trie, word)` returns `true` if the exact word has a positive weight, `false` otherwise. A stored "car" must NOT make `member?("ca")` return `true`.
- `AutocompleteTrie.suggest(trie, prefix, k)` returns up to `k` words that start with `prefix` (including `prefix` itself if it was inserted), ranked by **descending weight**, with ties broken **lexicographically ascending**. Returns a plain list of the word strings. `k` is a non-negative integer; `suggest(_, _, 0)` returns `[]`.
- `AutocompleteTrie.delete(trie, word)` removes `word` entirely (all of its weight) and returns the updated trie. Deleting "car" must not affect "card". Deleting an absent word is a no-op.
- `AutocompleteTrie.size(trie)` returns the count of distinct words currently stored (O(1)).
- `AutocompleteTrie.words(trie)` returns a sorted list of all words.

Suggested node shape: `%{children: %{char => node}, weight: non_neg_integer}`, where a positive `weight` marks the end of a word. The struct should also track the distinct-word count so `size/1` is O(1). Every operation returns a new trie without mutating the original.

No external dependencies. Single file with the `AutocompleteTrie` module.