**Ticket: `StrictConfigMerger` — conflict-detecting strict config merger**

Implement an Elixir module `StrictConfigMerger` that deep-merges two configuration maps but, instead of silently letting the override win everywhere, detects conflicts and reports them. Complete module in a single file; Elixir standard library only.

**Public API**
- `StrictConfigMerger.merge(base_config, override_config, opts \\ [])` is the one primary public function.
- Returns `{:ok, merged_map}` when there are no conflicts.
- Returns `{:error, conflicts}` where `conflicts` is a list of conflict maps sorted by their key-path.

**Deep-merge rules**
- Nested maps are deep-merged, not replaced wholesale.
- Scalars from `override_config` replace those in `base_config` at the same path.
- Lists follow the `:list_strategy` option: `:replace` (default) or `:append`.

**`:strict` option (boolean, default `false`)**
- When `true`: if both maps hold a value at the same key-path whose types differ — different scalar kinds (e.g. integer vs string), or a structural mismatch such as map-vs-scalar or list-vs-scalar — that is a `:type_mismatch` conflict.
- When `false`: such cases just let the override win with no conflict.
- Two maps, or two lists, are never a type mismatch (they merge per the rules above).

**`:locked` option (a list of key-path tuples/lists)**
- If `override_config` supplies a different value at a locked path (where the base already has a value), that is always a `:locked_violation` conflict, regardless of `:strict`.
- Supplying the same value, or not touching the path, is fine.

**`:required` option (a list of key-path tuples/lists)**
- Paths must be present in the merged result.
- Any missing one is a `:missing_required` conflict.

**Conflict shape**
- Each conflict is a map with at least `:type` (`:type_mismatch` | `:locked_violation` | `:missing_required`) and `:path` (a list of atoms).
- Type-mismatch and locked-violation conflicts should also include `:base` and `:override` values.
- When conflicts exist, return `{:error, conflicts_sorted_by_path}` and do not return a merged map.

**Path format**
- Key paths in `:locked`, `:required`, and `:list_strategies`-style options are lists or tuples of atoms.
