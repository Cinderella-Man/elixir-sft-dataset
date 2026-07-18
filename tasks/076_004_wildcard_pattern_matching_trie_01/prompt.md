Build me a **wildcard pattern-matching trie** in an Elixir module called `WildcardTrie`. On top of exact membership, it must support queries where a `.` in the pattern matches any single character — the classic "add and search word" data-structure design.

Keep it purely functional — no GenServer, no ETS. Just a struct and functions that return new tries.

API I need:

- `WildcardTrie.new()` returns an empty trie.
- `WildcardTrie.insert(trie, word)` inserts a word (string) and returns the updated trie.
- `WildcardTrie.member?(trie, word)` returns `true` only if the **exact literal** word was inserted. This performs no wildcard interpretation — a `.` in `word` matches only a literal `.`. A stored "car" must NOT make `member?("ca")` return `true`.
- `WildcardTrie.matches?(trie, pattern)` returns `true` if **any** stored word matches `pattern`, where each `.` in `pattern` matches exactly one arbitrary character (including a stored literal `.`). A pattern only matches words of the **same length** (there is no multi-char wildcard).
- `WildcardTrie.matching(trie, pattern)` returns a **sorted** list of every stored word that matches `pattern` (with `.` wildcards). A pattern with no `.` behaves like an exact lookup.
- `WildcardTrie.delete(trie, word)` removes an exact word and returns the updated trie. Deleting "car" must not affect "card". Deleting an absent word is a no-op.
- `WildcardTrie.size(trie)` returns the count of words currently stored (O(1)).
- `WildcardTrie.words(trie)` returns a sorted list of all words.

The empty string `""` is a valid word like any other: it can be inserted (bumping `size` to 1 and appearing in `words` and `matching(trie, "")`), reported by `member?` and `matches?`, and deleted. In a trie that does not contain it, `member?(trie, "")` returns `false`.

Suggested node shape: `%{children: %{char => node}, terminal: boolean}`, with the struct also tracking the word count so `size/1` is O(1). Wildcard search should branch into all children when it encounters a `.`. Every operation returns a new trie without mutating the original.

No external dependencies. Single file with the `WildcardTrie` module.
