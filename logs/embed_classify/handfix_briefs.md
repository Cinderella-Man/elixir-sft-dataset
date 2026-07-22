# Hand-fix briefs: 12 fix_child_gold dirs (parent redesigned at blanked target)
# Method per dir: new gold := parent's CURRENT function(s) of the same name;
# rebuild embed via resync_embeds logic; check prose still entails; re-gate family.

## tasks/021_001_versioned_api_with_content_negotiation_03
- target fn (from old gold): `render`; old gold heads: ['  def render(version, user) do']
- parent current `render` heads (2): ['def render("v1", u), do: %{name: u.first_name <> " " <> u.last_name, email: u.email}', 'def render("v2", u) do']
- verdict[real_drift/fix_child_gold]: Module-FIM target is render/2, and the parent redesigned it: the child gold and the embed stub both assume a single-clause `render(version, user)` with an internal `case version do` (child solution.ex:1-13; stub prompt.md:27-31), but the current parent implements render/2 as two pattern-matched clauses `render("v1", u), do: ...` and `render("v2", u) do ... end` (parent solution.ex:7,9-11). That is

## tasks/034_001_data_reconciliation_engine_02
- target fn (from old gold): `diff`; old gold heads: ['  defp diff(left, right, fields) do']
- parent current `diff` heads (1): ['defp diff(left, right, fields) do']
- verdict[real_drift/fix_child_gold]: Parent renamed its record type `record` -> `record_t`. The child's gold solution.ex still uses the old name in its diff/3 @spec, so the gold no longer appears verbatim in the parent and the checker's whitespace-normalized locator fails. That locator failure (empty gold_idx) is what leaves the blanked diff/3 body (parent solution.ex:151-160) flagged as 'missing from embed' — those body lines are a 

## tasks/034_001_data_reconciliation_engine_03
- target fn (from old gold): `resolve_compare_fields`; old gold heads: ['  defp resolve_compare_fields(_left, _right, _key_fields, compare_fields)', '  defp resolve_compare_fields(left, right, key_fields, nil) do']
- parent current `resolve_compare_fields` heads (2): ['defp resolve_compare_fields(_left, _right, _key_fields, compare_fields)', 'defp resolve_compare_fields(left, right, key_fields, nil) do']
- verdict[real_drift/fix_child_gold]: Same record->record_t rename. The gold's resolve_compare_fields/4 @spec uses the old name `record()`, so the whitespace-normalized locator cannot find the gold in the parent; the resulting empty gold_idx leaves the blanked-region lines (parent solution.ex:134-144) flagged as 'missing from embed'. Those lines are byte-identical between gold and parent — the only genuine difference is the stale type

## tasks/034_001_data_reconciliation_engine_04
- target fn (from old gold): `composite_key`; old gold heads: ['  defp composite_key(record, key_fields) do']
- parent current `composite_key` heads (1): ['defp composite_key(record, key_fields) do']
- verdict[real_drift/fix_child_gold]: Same record->record_t rename. The gold's composite_key/2 @spec uses the old name `record()`, breaking the whitespace-normalized locator; the empty gold_idx leaves the blanked body (parent solution.ex:125-127) flagged as 'missing from embed', though that body is byte-identical between gold and parent. The genuine drift is solely the stale type name in the gold @spec. The embed matches the parent (v

## tasks/038_001_tree_structure_builder_from_flat_list_02
- target fn (from old gold): `build`; old gold heads: ['  def build([], _opts), do: {:ok, []}', '  def build(items, opts) when is_list(items) do']
- parent current `build` heads (3): ['def build(items, opts \\\\ [])', 'def build([], _opts), do: {:ok, []}', 'def build(items, opts) when is_list(items) do']
- verdict[real_drift/fix_child_gold]: Module-FIM child whose gold (solution.ex) is the blanked build/2 target. The child gold's build/2 matches the current parent build/2 in every line EXCEPT the root_ids computation: the child gold uses a direct call `Enum.filter(ordered_ids, fn id -> ...)` with single-line cond clauses, whereas the current parent uses pipe form `ordered_ids |> Enum.filter(fn id -> ...)` with a multi-line cond. Pipe-

## tasks/039_001_diff_generator_for_record_lists_02
- target fn (from old gold): `diff_records`; old gold heads: ['  defp diff_records(old_record, new_record) do']
- parent current `diff_records` heads (1): ['defp diff_records(old_record, new_record) do']
- verdict[real_drift/fix_child_gold]: The module-FIM embed already matches the current parent (record_t everywhere), so the embed is NOT stale. The child's gold solution.ex is stale: its @spec references type record(), while the parent module declares @type record_t. The diff_records def body in the gold is byte-identical to the parent. The @spec mismatch is what stopped the checker from locating the gold ('child gold not located'), a

## tasks/039_001_diff_generator_for_record_lists_04
- target fn (from old gold): `diff`; old gold heads: ['  def diff(old_list, new_list, opts \\\\ []) do']
- parent current `diff` heads (1): ['def diff(old_list, new_list, opts \\\\ []) do']
- verdict[real_drift/fix_child_gold]: Same pattern as _02 but for diff/3. The embed matches the current parent (record_t). The child gold solution.ex @spec references record() where the parent uses record_t(); the def body is byte-identical to the parent. The stale @spec caused the locator to fail, so the checker dumped the blanked body lines 57-73 as 'missing from embed' as locator-failure noise. The one real drift is the stale @spec

## tasks/072_001_test_helper_for_time_dependent_code_03
- target fn (from old gold): `now`; old gold heads: ['  def now(clock) do']
- parent current `now` heads (4): ['def now(clock) when is_atom(clock) do', 'def now(clock), do: Clock.Fake.now(clock)', 'def now, do: DateTime.utc_now()', 'def now(server), do: GenServer.call(server, :now)']
- verdict[real_drift/fix_child_gold]: The parent (01) was redesigned at the blanked target now/1 AFTER this child was minted. The parent now uses a two-clause guard-based dispatch: `def now(clock) when is_atom(clock) do` (with an inner `if function_exported?(clock, :now, 0)` and explanatory # comments) plus a separate catch-all `def now(clock), do: Clock.Fake.now(clock)`. The child's gold (solution.ex) is still the OLD single guardles

## tasks/091_001_workflow_state_machine_03
- target fn (from old gold): `guard`; old gold heads: ['  defp guard(:submit, %{items: items}) when is_list(items) and items != [], do: true', '  defp guard(:submit, _record), do: false', '  defp guard(:approve, %{approved_by: by}) when is_binary(by) and by != "", do: true']
- parent current `guard` heads (5): ['defp guard(:submit, %{items: items}) when is_list(items) and items != [], do: true', 'defp guard(:submit, _record), do: false', 'defp guard(:approve, %{approved_by: approved_by})', 'defp guard(:approve, _record), do: false', 'defp guard(_event, _record), do: true']
- verdict[real_drift/fix_child_gold]: The parent was edited at the blanked target (guard/2) after this module-FIM child was minted, so the child gold no longer matches the parent's function. The only real difference is the :approve clause: the child gold binds the variable `by` on a single line, while the current parent binds `approved_by` and wraps the guard across three lines. A variable rename (by -> approved_by) is a genuine sourc

## tasks/091_002_reversible_order_workflow_with_undo_history_03
- target fn (from old gold): `new`; old gold heads: ['  def new(attrs \\\\ %{}) when is_map(attrs) do', '  def states, do: @states', '  def transition(%{state: current, history: history} = record, event) do']
- parent current `new` heads (1): ['def new(attrs \\\\ %{}) when is_map(attrs) do']
- verdict[real_drift/fix_child_gold]: The surviving diff is the whole blanked guard/2 region (parent solution.ex lines 86-95). It survived only because gold_indices/2 could not locate the child gold, so rule (b) never subtracted the blanked-function region. There is NO genuine semantic drift at the target: the parent's guard/2 clauses are byte-identical to the child gold's guard/2 clauses (parent was redesigned at new/1, not at guard/

## tasks/091_003_data_driven_finite_state_machine_engine_04
- target fn (from old gold): `define`; old gold heads: ['  def define(initial, transitions) when is_atom(initial) and is_list(transitions) do', '  defp normalize({event, from, to})', '  defp normalize({event, from, to, guard})']
- parent current `define` heads (1): ['def define(initial, transitions) when is_atom(initial) and is_list(transitions) do']
- verdict[real_drift/fix_child_gold]: The child gold solution.ex is not the isolated blanked function — it is the ENTIRE parent Workflow module (80 lines). A read-only diff shows it is byte-identical to the parent except it is missing the parent's one-line @doc on define/2 (parent solution.ex:20) and the trailing newline, i.e. it is a stale full-module snapshot taken before the parent gained that @doc line. Because the checker's rule 

## tasks/131_003_parallel_streaming_json_array_parser_04
- target fn (from old gold): `throughput`; old gold heads: ['  defp throughput(processed, elapsed_ms) do']
- parent current `throughput` heads (3): ['defp throughput(_processed, +0.0), do: 0.0', 'defp throughput(_processed, 0), do: 0.0', 'defp throughput(processed, elapsed_ms), do: processed / (elapsed_ms / 1000)']
- verdict[real_drift/fix_child_gold]: The parent was redesigned at the blanked target function throughput/2. The parent now implements it as three pattern-matched clauses (defp throughput(_processed, +0.0)/0.0; defp throughput(_processed, 0)/0.0; defp throughput(processed, elapsed_ms), do: ...), while both the child 04 embed and the child 04 gold still reflect the OLD single-clause `if elapsed_ms == 0 ... else ... end` design. The emb

