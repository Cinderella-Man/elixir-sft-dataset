Write me an Elixir module called `ConfigStore` implemented as a **GenServer** that
holds a base configuration plus a dynamic, ordered set of named override layers and
computes the deep-merged effective configuration on demand.

Public API:
- `ConfigStore.start_link(opts)` — starts the server. Supported opts:
  - `:base` — the base config map (default `%{}`).
  - `:name` — optional GenServer name.
  - `:list_strategy` — `:replace` (default) or `:append`, global list merge strategy.
  - `:list_strategies` — a map of `key_path => :replace | :append` (paths as lists or
    tuples of atoms) overriding the global strategy per path.
  - `:locked` — a list of key-path tuples/lists that override layers must not change.
- `ConfigStore.put_layer(server, layer_name, config_map)` — adds a named override
  layer, or replaces an existing one **in place** (keeping its precedence position).
  Returns `:ok`.
- `ConfigStore.drop_layer(server, layer_name)` — removes a layer. Returns `:ok`.
- `ConfigStore.layers(server)` — returns the list of layer names in precedence order
  (lowest precedence first).
- `ConfigStore.get_config(server)` — returns the deep-merged effective config: the
  base with every layer applied in order, later layers winning.
- `ConfigStore.get(server, key_path)` — returns the effective value at a key-path
  (list of atoms), or `nil` if absent.

Merge rules match a standard deep config merge:
- Nested maps are deep-merged, not replaced wholesale.
- Scalars from higher-precedence layers replace lower ones.
- Lists follow the `:list_strategy` / `:list_strategies` options (`:append`
  concatenates onto the accumulated list).
- Locked key-paths keep the base value and cannot be changed by any layer. Locking
  applies to the exact full key-path only (siblings under the same parent are still
  free to change). If the base does not define a locked path, no layer may introduce
  it — the effective value there stays absent (`get` returns `nil`).

Layers apply in insertion order: the first `put_layer` is lowest precedence; a later
`put_layer` with the same name updates the existing layer without changing its spot.
Re-putting a layer replaces its whole config map (stale keys from the previous map
are dropped), not merged with the old one.

Give me the complete module in a single file. Use only the Elixir standard library.
