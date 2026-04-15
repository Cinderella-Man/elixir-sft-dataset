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
