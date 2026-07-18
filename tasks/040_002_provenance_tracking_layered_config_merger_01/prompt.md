Write me an Elixir module called `LayeredConfig` that merges an ordered stack of
named configuration layers into a single effective configuration **and reports the
provenance** of every effective value (which layer it came from).

I need one primary public function:
- `LayeredConfig.merge(layers, opts \\ [])` where `layers` is a non-empty list of
  `{layer_name, config_map}` tuples given in **increasing precedence order** (the
  first tuple is the base, each later layer overrides the ones before it).

It must return a map with exactly two keys:
- `:config` — the deep-merged effective configuration map.
- `:provenance` — a map from **key-path** (a list of atoms from root to a leaf,
  e.g. `[:db, :port]`) to the name of the layer that supplied the winning value.

The merging rules:
- **Deep merging**: if two layers both hold a map at the same key, recurse into it
  rather than replacing the whole map.
- **Later layers win** for scalars (strings, integers, atoms, booleans): the value
  from the highest-precedence layer that set the leaf wins, and provenance records
  that layer's name.
- **Subtree replaced by a leaf**: when a higher layer overrides an entire subtree
  (a map in a lower layer) with a scalar or list, the winning value replaces the
  whole subtree, provenance records the new leaf path pointing at that layer, and
  every provenance entry for paths nested beneath the replaced subtree is dropped.
- **List strategy**: controlled by the `:list_strategy` option, either `:replace`
  (default, higher layer's list wins) or `:append` (higher layer's list is
  concatenated onto the accumulated list). For an appended leaf, its provenance is
  the **list of layer names** (in precedence order) that contributed elements —
  layers that set no list at that path are omitted from the list.
- **Per-key list strategy**: the `:list_strategies` option accepts a map of
  `key_path => :replace | :append` (key paths as lists or tuples of atoms) that
  overrides the global `:list_strategy` for those specific paths.
- **Locked keys**: the `:locked` option accepts a list of key-path tuples/lists.
  When a locked path already exists in a lower-precedence layer, higher layers must
  not change it — the earlier value and its provenance are preserved. Locking only
  applies where the key already exists in an earlier layer.

Key paths for `:list_strategies` and `:locked` are lists (or tuples) of atoms from
root to the target key.

A single-layer stack must return that layer's config unchanged with every leaf's
provenance pointing at that one layer. Raise `ArgumentError` on an empty layer list.

Give me the complete module in a single file. Use only the Elixir standard library.
