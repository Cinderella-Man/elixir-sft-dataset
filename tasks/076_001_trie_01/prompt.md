Build me a Trie (prefix tree) data structure Elixir module called `Trie`. I want a pure functional implementation — no GenServer or ETS, just a struct and functions that return new tries.

Here's the API I need:

- `Trie.new()` returns an empty trie
- `Trie.insert(trie, word)` inserts a word (string) and returns the updated trie. Inserting a word that's already present is a no-op: the size stays the same and the word still appears only once in `words` and `search`. The empty string `""` is a valid word — inserting it makes it a member, counts toward `size`, and shows up as `""` in `words`.
- `Trie.member?(trie, word)` returns true if the exact word was inserted, false otherwise. The word "car" being present should NOT make `member?("ca")` return true unless "ca" was also inserted separately. The empty string is a member only if `""` was itself inserted.
- `Trie.search(trie, prefix)` returns a sorted list of all words in the trie that start with the given prefix. If the prefix itself was inserted as a word, include it too. Searching with an empty prefix (`search(trie, "")`) returns every word in the trie, sorted. A prefix that matches nothing (including a prefix longer than any stored word) returns `[]`.
- `Trie.delete(trie, word)` removes a word and returns the updated trie. Deleting "car" should not affect "card" if "card" is also in the trie — only the end-of-word marker for "car" should be removed, shared prefix nodes stay. Deleting a word that isn't in the trie — including deleting the same word twice or deleting from an empty trie — is a no-op that leaves the trie unchanged; `size` never goes below zero.
- `Trie.size(trie)` returns the integer count of words currently in the trie
- `Trie.words(trie)` returns a sorted list of all words in the trie

Implementation-wise I'd expect the trie to be a nested map structure where each node is a map of `%{children: %{char => node}, end_of_word: boolean}` or similar. The key thing is it needs to be purely functional — every operation returns a new trie without mutating the original.

No external dependencies. Single file with the `Trie` module.
