Build me a **compressed radix trie** (a Patricia-style prefix tree) in an Elixir module called `RadixTrie`. Unlike a plain character-per-node trie, this one must **path-compress**: any chain of single-child nodes is collapsed into one edge labeled with a multi-character string. This keeps the tree shallow and the node count small, which is the whole point of the exercise.

Keep it purely functional — no GenServer, no ETS. Just a struct and functions that return new tries.

API I need:

- `RadixTrie.new()` returns an empty trie.
- `RadixTrie.insert(trie, word)` inserts a word (string) and returns the updated trie. Inserting a word that shares a prefix with an existing edge must **split** that edge as needed so the compression invariant holds.
- `RadixTrie.member?(trie, word)` returns `true` only if the exact word was inserted. A stored word "car" must NOT make `member?("ca")` return `true` unless "ca" was inserted on its own.
- `RadixTrie.search(trie, prefix)` returns a sorted list of every word that starts with `prefix` (including `prefix` itself if it was inserted). The prefix may end in the *middle* of a compressed edge — that must still work.
- `RadixTrie.delete(trie, word)` removes a word and returns the updated trie. Deleting "car" must not affect "card". After a deletion, if a node is left with a single child, **re-merge** the edges so the compression invariant is restored. Deleting an absent word is a no-op.
- `RadixTrie.size(trie)` returns the count of words currently stored (O(1)).
- `RadixTrie.words(trie)` returns a sorted list of all words.
- `RadixTrie.node_count(trie)` returns the total number of nodes in the tree (including the root). Because of compression, this must be much smaller than the total character count when words share prefixes.

Suggested node shape: `%{edges: %{first_char => %{label: binary, child: node}, ...}, terminal: boolean}`, with the struct also tracking the word count so `size/1` is O(1). Every operation returns a new trie without mutating the original.

No external dependencies. Single file with the `RadixTrie` module.