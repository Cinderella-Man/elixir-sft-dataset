Write me an Elixir module called `ConfigMerger` that deep-merges configuration maps with a configurable override strategy.

I need one primary public function:
- `ConfigMerger.merge(base_config, override_config, opts \\ [])` which deep-merges two maps and returns the merged result.

The merging rules are:
- **Later sources win by default**: scalar values (strings, integers, atoms, booleans) in `override_config` replace those in `base_config` at the same key path.
- **Deep merging**: if both `base_config` and `override_config` have a map at the same key, recurse into it rather than replacing the whole map.
- **List strategy**: lists can be merged in two ways, controlled by the `:list_strategy` option. The default is `:replace` (override list replaces base list). If set to `:append`, the override list is appended to the base list. The strategy applies uniformly to all lists unless overridden per-key (see below).
- **Per-key list strategy**: the `:list_strategies` option accepts a map where keys are key-path tuples (e.g. `{:servers, :hosts}` for a nested key) and values are `:replace` or `:append`. These take precedence over the global `:list_strategy`.
- **Locked keys**: the `:locked` option accepts a list of key-path tuples (e.g. `[:database, :password]` meaning the key `:password` nested under `:database`). Any key whose full path matches a locked path must not be overridden — the base value must be preserved. Locking a key at a given path does not affect the same key at a different path.

The key-path tuple convention for both `:list_strategies` and `:locked` is a list of atoms representing the nesting from root to the target key, e.g. `[:a, :b, :c]` refers to `base_config.a.b.c`.

Return the merged map directly — no wrapping in `{:ok, ...}` tuples needed.

Give me the complete module in a single file. Use only the Elixir standard library, no external dependencies.