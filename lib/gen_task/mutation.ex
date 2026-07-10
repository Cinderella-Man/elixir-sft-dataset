defmodule GenTask.Mutation do
  @moduledoc """
  The mutation gate (see `docs/04-task-generation-loop.md` §13).

  Reuses `EvalTask.Fim.mutate/1` (every `def/defp/defmacro(p)` body → `raise`) to
  prove a harness actually exercises the code:

    * **base / variation** — mutate the whole `solution.ex`, stage it with the SAME
      harness, grade; a genuine harness must FAIL. If it passes, the harness is
      vacuous.
    * **FIM** — mutate the candidate function, grade the `_0d` dir with the mutant as
      an override solution; the parent harness must FAIL. If it passes, the parent
      harness does not cover the target → reject the candidate.

  Each helper returns `:killed` (mutant failed — good) or `:survived` (mutant passed
  — bad).
  """

  require Logger

  alias EvalTask.Bundle
  alias GenTask.{Config, Evaluator}

  @type result :: :killed | {:survived, String.t()}

  @doc """
  Produce a whole-solution mutant of `solution_src` (every `def/defp/defmacro(p)`
  body → `raise`).

  Handles both shapes:

    * **plain module** — mutate the raw source AST directly. Unlike
      `EvalTask.Fim.mutate/1` this does **not** run the FIM candidate extraction
      (`extract_candidate/1`) first: on a whole module that regex would grab the
      first column-0 ```` ```elixir ```` fence — commonly a `@moduledoc`/`@doc`
      example — and discard the entire module, yielding a non-compiling "mutant"
      that is always `:killed` and so silently defeats the gate.
    * **`<file>` bundle** — the raw bundle string is not valid Elixir, so parsing it
      whole raises and (historically) fell through to the rescue below, returning the
      source **unchanged** → the "mutant" was byte-identical to the solution, always
      graded `:survived`, and every multi-file harness was mislabelled vacuous. We now
      parse the bundle and gut the `lib/**/*.ex` module bodies file-by-file, leaving
      migrations/config intact, then re-emit the bundle.

  On a rescue we return the source **unchanged** so the mutant grades green
  (`:survived`) and is flagged as a vacuous harness — a conservative outcome that
  never wrongly accepts.
  """
  @spec mutate(String.t()) :: String.t()
  def mutate(solution_src) do
    if Bundle.bundle?(solution_src),
      do: mutate_bundle(solution_src),
      else: mutate_module_src(solution_src, plug_module?(solution_src))
  rescue
    _ -> solution_src
  end

  # Gut every `def/defp/defmacro(p)` body of a single module source to `raise`,
  # except compile-time-invoked callbacks (see `compile_time_callback?/2`). `plug?`
  # is whether THIS module is a Plug (per-file for bundles): only then is `init/1`
  # exempt — a GenServer/plain module's `init/1` is real logic and gets gutted.
  defp mutate_module_src(module_src, plug?) do
    module_src
    |> Code.string_to_quoted!()
    |> Macro.prewalk(&mutate_module_node(&1, plug?))
    |> Macro.to_string()
  end

  defp mutate_module_node({d, m, [head, kw]}, plug?)
       when d in [:def, :defp, :defmacro, :defmacrop] and is_list(kw) do
    if Keyword.has_key?(kw, :do) and not compile_time_callback?(head, plug?),
      do: {d, m, [head, [do: quote(do: raise("MUTATION"))]]},
      else: {d, m, [head, kw]}
  end

  defp mutate_module_node(node, _plug?), do: blank_docs(node)

  # `@doc`/`@moduledoc`/`@typedoc` bodies are re-serialized by `Macro.to_string`, and an
  # interpolated or heredoc doc with `iex>` code examples can round-trip to *invalid*
  # syntax — the mutant then fails to parse/compile and is misread as inconclusive (a
  # false "vacuous" flag). Docs never affect runtime behavior, so blank them to `false`
  # before re-emitting. Matches every value shape (string, sigil, interpolation).
  defp blank_docs({:@, m, [{doc, dm, [_v]}]}) when doc in [:doc, :moduledoc, :typedoc],
    do: {:@, m, [{doc, dm, [false]}]}

  defp blank_docs(node), do: node

  # `Plug.Builder` invokes each plug's `init/1` at COMPILE time and inlines the result,
  # so a gutted `init/1` raises *during compilation* — the mutant never compiles and the
  # gate reads it as inconclusive rather than killed. Leave a *Plug's* `init/1` intact: the
  # tested request logic lives in `call/2`/handlers, which are still gutted, so a genuine
  # harness is still killed. This exemption is Plug-ONLY (`plug?`) — a GenServer's `init/1`
  # runs at RUNTIME and holds real state-construction logic, so it is gutted like any other
  # function; the blanket exemption previously left GenServer startup semantics unverified.
  defp compile_time_callback?(head, plug?), do: plug? and head_name_arity(head) == {:init, 1}

  # Mutate a `<file>` bundle: gut the module bodies of every `lib/**/*.ex` file and
  # re-emit the bundle unchanged elsewhere (migrations/config/priv left intact so the
  # mutant still compiles and boots — only the solution *logic* is destroyed). A bundle
  # that parses to no blocks is returned unchanged (conservative → survived).
  defp mutate_bundle(bundle_src) do
    case Bundle.parse(bundle_src) do
      [] ->
        bundle_src

      files ->
        files
        |> Enum.map_join("\n\n", fn {path, body} ->
          new_body =
            if String.starts_with?(path, "lib/") and String.ends_with?(path, ".ex"),
              do: mutate_module_src(body, plug_module?(body)),
              else: body

          ~s(<file path="#{path}">\n#{new_body}\n</file>)
        end)
    end
  end

  # ── semantic mutants (assertion tightness, docs/10 R10) ─────────────────────

  @semantic_cap 40

  # Typespec attributes carry no runtime behavior — a mutant that only touches a
  # `@spec`/`@type` compiles and behaves identically, i.e. a guaranteed survivor
  # that would only add noise to the kill-rate.
  @typespec_attrs [:spec, :type, :typep, :opaque, :callback, :macrocallback]

  @doc """
  First-order semantic mutants of `solution_src` (plain module or `<file>` bundle):
  a list of `{label, mutated_source}` pairs, each differing from the source at
  exactly ONE site. Unlike raise-mutants (which prove a harness *invokes* a
  function), semantic mutants measure whether its assertions actually *pin
  behavior* — a survived semantic mutant is a behavior change no test noticed.

  Operators (applied at every applicable site, one mutation per mutant):

    * comparison swap — `<` ↔ `<=`, `>` ↔ `>=`
    * integer literal ±1 — only literals `0..1000` (larger ones are config-scale
      noise); `+1` at every site, `-1` additionally for literals `> 0`
    * `:ok` ↔ `:error` — as the first element of a tuple literal, or as a bare
      return atom (clause body, `do:`/`else:` value, or last expression of a block)
    * boolean flip — `true` ↔ `false`, skipped inside module attributes

  No mutation is generated inside `@moduledoc`/`@doc`/`@typedoc` (blanked, as in
  `mutate/1`), typespec attributes, strings/binaries, or charlists. Every emitted
  mutant is re-parsed with `Code.string_to_quoted/1`; ones that do not parse are
  dropped, and duplicates (two sites collapsing to the same output) are de-duped.

  Output is deterministic and capped at `limit` (default #{@semantic_cap}) per
  module via an even spread across sites — not the first N, which would bias the
  sample toward the top of the file. For a bundle, each `lib/**/*.ex` file is
  mutated independently (one mutant = one mutated file re-embedded in the bundle,
  label prefixed with the file path) and the spread cap applies to the total.

  `[]` on a parse error (conservative: nothing to measure).
  """
  @spec semantic_mutants(String.t(), pos_integer()) :: [{String.t(), String.t()}]
  def semantic_mutants(solution_src, limit \\ @semantic_cap) do
    if Bundle.bundle?(solution_src),
      do: semantic_mutants_bundle(solution_src, limit),
      else: semantic_mutants_module(solution_src, limit)
  rescue
    _ -> []
  end

  defp semantic_mutants_module(module_src, limit) do
    # Blank docs up front (same reason as `mutate/1`: heredoc docs can round-trip
    # to invalid syntax) — the baseline and every mutant share the blanking, so a
    # mutant still differs from the baseline at exactly one site.
    ast = module_src |> Code.string_to_quoted!() |> Macro.prewalk(&blank_docs/1)
    baseline = Macro.to_string(ast)

    ast
    |> enumerate_sites()
    |> spread(limit)
    |> Enum.map(fn {ix, spec, line} ->
      {site_label(ix, spec, line), ast |> apply_at(ix, spec) |> Macro.to_string()}
    end)
    |> Enum.reject(fn {_label, src} -> src == baseline end)
    |> Enum.filter(fn {_label, src} -> match?({:ok, _}, Code.string_to_quoted(src)) end)
    |> Enum.uniq_by(fn {_label, src} -> src end)
  rescue
    _ -> []
  end

  # One mutant = one mutated lib file re-embedded into the otherwise-unchanged
  # bundle. Module sources are parse-checked before embedding (the bundle itself
  # is not valid Elixir, so the check must happen at the module level).
  defp semantic_mutants_bundle(bundle_src, limit) do
    files = Bundle.parse(bundle_src)

    all =
      for {path, body} <- files,
          String.starts_with?(path, "lib/") and String.ends_with?(path, ".ex"),
          {label, mutated} <- semantic_mutants_module(body, limit),
          do: {"#{path} #{label}", reemit_bundle(files, path, mutated)}

    spread(all, limit)
  end

  defp reemit_bundle(files, target_path, new_body) do
    Enum.map_join(files, "\n\n", fn {path, body} ->
      emitted = if path == target_path, do: new_body, else: body
      ~s(<file path="#{path}">\n#{emitted}\n</file>)
    end)
  end

  # Enumerate mutation sites as `{site_index, spec, line}`. The site index is the
  # prewalk visit ordinal of the node (counted for EVERY node, skipped or not), so
  # the application pass — a plain `Macro.prewalk/3` with the same counter — lands
  # on the identical node. `skip` tracks strings/binaries/charlists/typespecs
  # (no mutations at all inside); `attr` tracks module-attribute values (boolean
  # flips only are suppressed there — `@impl true` etc. are not behavior).
  defp enumerate_sites(ast) do
    {_ast, {_ix, _skip, _attr, sites}} =
      Macro.traverse(ast, {0, 0, 0, []}, &enum_pre/2, &enum_post/2)

    Enum.reverse(sites)
  end

  defp enum_pre(node, {ix, skip, attr, sites}) do
    cond do
      skip_all?(node) ->
        {node, {ix + 1, skip + 1, attr, sites}}

      attr?(node) ->
        {node, {ix + 1, skip, attr + 1, sites}}

      skip > 0 ->
        {node, {ix + 1, skip, attr, sites}}

      true ->
        found = for spec <- node_mutations(node, attr > 0), do: {ix, spec, node_line(node)}
        {node, {ix + 1, skip, attr, Enum.reverse(found, sites)}}
    end
  end

  defp enum_post(node, {ix, skip, attr, sites}) do
    cond do
      skip_all?(node) -> {node, {ix, skip - 1, attr, sites}}
      attr?(node) -> {node, {ix, skip, attr - 1, sites}}
      true -> {node, {ix, skip, attr, sites}}
    end
  end

  defp skip_all?({:@, _, [{name, _, [_ | _]}]}) when name in @typespec_attrs, do: true
  defp skip_all?({:<<>>, _, _}), do: true
  defp skip_all?(list) when is_list(list), do: list != [] and List.ascii_printable?(list)
  defp skip_all?(_), do: false

  defp attr?({:@, _, [{name, _, [_ | _]}]}) when is_atom(name), do: true
  defp attr?(_), do: false

  # The mutation specs a single AST node admits (each spec → one mutant).
  defp node_mutations({op, _, [_, _]}, _attr?) when op in [:<, :<=, :>, :>=],
    do: [{:cmp, op}]

  defp node_mutations(n, _attr?) when is_integer(n) and n >= 0 and n <= 1000 do
    if n > 0, do: [{:int, n, 1}, {:int, n, -1}], else: [{:int, n, 1}]
  end

  defp node_mutations(b, attr?) when is_boolean(b),
    do: if(attr?, do: [], else: [{:bool, b}])

  defp node_mutations({first, _}, _attr?) when first in [:ok, :error],
    do: [{:pair, first}]

  defp node_mutations({:{}, _, [first | _]}, _attr?) when first in [:ok, :error],
    do: [{:tuple, first}]

  defp node_mutations({:->, _, [_, body]}, _attr?) when body in [:ok, :error],
    do: [{:ret, body}]

  defp node_mutations({key, body}, _attr?) when key in [:do, :else] and body in [:ok, :error],
    do: [{:ret, body}]

  defp node_mutations({:__block__, _, [_ | _] = exprs}, _attr?) do
    case List.last(exprs) do
      a when a in [:ok, :error] -> [{:blockret, a}]
      _ -> []
    end
  end

  defp node_mutations(_node, _attr?), do: []

  # Re-walk with the same visit counter and rewrite the single target node. Nodes
  # after the target may then be counted differently — irrelevant, the mutation is
  # already applied. A spec that no longer matches leaves the node unchanged; the
  # emitted "mutant" then equals the baseline and is rejected by the caller.
  defp apply_at(ast, target_ix, spec) do
    {mutated, _ix} =
      Macro.prewalk(ast, 0, fn node, ix ->
        if ix == target_ix,
          do: {apply_mutation(node, spec), ix + 1},
          else: {node, ix + 1}
      end)

    mutated
  end

  defp apply_mutation({op, m, [l, r]}, {:cmp, op}), do: {swap_cmp(op), m, [l, r]}
  defp apply_mutation(n, {:int, n, d}) when is_integer(n), do: n + d
  defp apply_mutation(b, {:bool, b}), do: not b
  defp apply_mutation({a, rest}, {:pair, a}), do: {flip_ok(a), rest}
  defp apply_mutation({:{}, m, [a | rest]}, {:tuple, a}), do: {:{}, m, [flip_ok(a) | rest]}
  defp apply_mutation({:->, m, [args, a]}, {:ret, a}), do: {:->, m, [args, flip_ok(a)]}
  defp apply_mutation({key, a}, {:ret, a}), do: {key, flip_ok(a)}

  defp apply_mutation({:__block__, m, exprs}, {:blockret, a}),
    do: {:__block__, m, List.replace_at(exprs, -1, flip_ok(a))}

  defp apply_mutation(node, _spec), do: node

  defp swap_cmp(:<), do: :<=
  defp swap_cmp(:<=), do: :<
  defp swap_cmp(:>), do: :>=
  defp swap_cmp(:>=), do: :>

  defp flip_ok(:ok), do: :error
  defp flip_ok(:error), do: :ok

  defp node_line({_, meta, _}) when is_list(meta), do: meta[:line]
  defp node_line(_), do: nil

  defp site_label(ix, spec, line) do
    at = if line, do: "L#{line} s#{ix}", else: "s#{ix}"
    "#{at}: #{describe_spec(spec)}"
  end

  defp describe_spec({:cmp, op}), do: "#{op} -> #{swap_cmp(op)}"
  defp describe_spec({:int, n, d}), do: "#{n} -> #{n + d}"
  defp describe_spec({:bool, b}), do: "#{b} -> #{not b}"
  defp describe_spec({:pair, a}), do: "{:#{a}, _} -> {:#{flip_ok(a)}, _}"
  defp describe_spec({:tuple, a}), do: "{:#{a}, ...} -> {:#{flip_ok(a)}, ...}"
  defp describe_spec({:ret, a}), do: "return :#{a} -> :#{flip_ok(a)}"
  defp describe_spec({:blockret, a}), do: "return :#{a} -> :#{flip_ok(a)}"

  # Deterministic even spread of at most `limit` items — indices `div(i*n, limit)`
  # are strictly increasing for n > limit, so no duplicates and full-range coverage
  # (first-N would bias the sample toward the top of the file).
  defp spread(list, limit) do
    n = length(list)

    if n <= limit do
      list
    else
      arr = List.to_tuple(list)
      for i <- 0..(limit - 1), do: elem(arr, div(i * n, limit))
    end
  end

  @doc """
  Replace the body of every clause of the function `name/arity` (of the given `kind`,
  `:def` by default, `:defp` for a private fn) with `raise`, leaving all other functions
  intact. Used by the per-function and isolation gates. On a parse error the source is
  returned unchanged (conservative — the mutant grades green and is flagged `:survived`).
  """
  @spec mutate_fn(String.t(), atom(), non_neg_integer(), :def | :defp) :: String.t()
  def mutate_fn(solution_src, name, arity, kind \\ :def) do
    solution_src
    |> Code.string_to_quoted!()
    |> Macro.prewalk(fn
      {^kind, m, [head, kw]} = node when is_list(kw) ->
        if head_name_arity(head) == {name, arity} and Keyword.has_key?(kw, :do),
          do: {kind, m, [head, [do: quote(do: raise("MUTATION"))]]},
          else: node

      # blank docs so the surrounding module still round-trips to valid syntax
      other ->
        blank_docs(other)
    end)
    |> Macro.to_string()
  rescue
    _ -> solution_src
  end

  @doc """
  The `{kind, name, arity}` of every function (`def` **and** `defp`) defined in
  `solution_src`, de-duplicated across clauses. `[]` on a parse error. Used by the
  test-FIM isolation gate, where a single test may exercise private helpers only.
  """
  @spec all_functions(String.t()) :: [{:def | :defp, atom(), non_neg_integer()}]
  def all_functions(solution_src) do
    {_ast, acc} =
      solution_src
      |> Code.string_to_quoted!()
      |> Macro.prewalk([], fn
        {kind, _m, [head | _]} = node, acc when kind in [:def, :defp] ->
          case head_name_arity(head) do
            {n, a} -> {node, [{kind, n, a} | acc]}
            nil -> {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    acc |> Enum.reverse() |> Enum.uniq()
  rescue
    _ -> []
  end

  @doc """
  The `{name, arity}` of every **public** function (`def`, not `defp`/macros) defined
  in `solution_src`, de-duplicated across clauses. `[]` on a parse error.
  """
  @spec public_functions(String.t()) :: [{atom(), non_neg_integer()}]
  def public_functions(solution_src) do
    {_ast, acc} =
      solution_src
      |> Code.string_to_quoted!()
      |> Macro.prewalk([], fn
        {:def, _m, [head | _]} = node, acc ->
          case head_name_arity(head) do
            {_n, _a} = na -> {node, [na | acc]}
            nil -> {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    acc |> Enum.reverse() |> Enum.uniq()
  rescue
    _ -> []
  end

  # Extract {name, arity} from a function head AST, handling a `when` guard.
  # Public (@doc false) — GenTask.Fim's skeleton-integrity check reuses it.
  @doc false
  def head_name_arity({:when, _, [inner | _]}), do: head_name_arity(inner)

  def head_name_arity({name, _, args}) when is_atom(name) and is_list(args),
    do: {name, length(args)}

  def head_name_arity({name, _, nil}) when is_atom(name), do: {name, 0}
  def head_name_arity(_), do: nil

  @doc """
  Base/variation gate. `files` is the accepted triplet; `mutant_dir` is a staging
  directory (must be outside `tasks/`).

  When `cfg.per_fn_mutation` is set (the default), mutate **each public function
  independently** and require every one's raise-mutant to make the harness fail —
  proving the harness exercises the whole public API, not just one function (a
  whole-module mutant is killed as soon as *any* single function is asserted). Falls
  back to a whole-module mutant when no public functions can be parsed, or when
  per-function mutation is disabled.

  Returns `:killed` when every mutant failed (harness is genuine), or
  `{:survived, reason}` naming the uncovered function (or whole-module).
  """
  @spec gate_base(String.t(), %{String.t() => String.t()}, Config.t()) :: result()
  def gate_base(mutant_dir, files, %Config{} = cfg) do
    case base_mode(files["solution.ex"], cfg) do
      # A bundle's public API spans several modules; `public_functions`/`mutate_fn`
      # are single-module only, so per-fn mutation cannot address it. `mutate/1`
      # gutting every lib module is the whole-solution coverage check for bundles.
      :whole -> gate_base_whole(mutant_dir, files, cfg)
      :per_fn -> gate_base_per_fn(mutant_dir, files, per_fn_targets(files["solution.ex"]), cfg)
    end
  end

  @doc """
  Whether `gate_base/3` runs a **per-function** or a **whole-solution** raise-mutation
  sweep for `solution_src` under `cfg` — the single source of truth for the gate's
  dispatch AND for the honest mutation-mode label recorded in the ledger
  (docs/12 §5.1 item 5). `:whole` when per-function mutation is disabled, the solution
  is a `<file>` bundle (multi-module API), or no per-function targets parse; `:per_fn`
  otherwise.
  """
  @spec base_mode(String.t(), Config.t()) :: :per_fn | :whole
  def base_mode(solution_src, %Config{per_fn_mutation: true}) do
    cond do
      Bundle.bundle?(solution_src) -> :whole
      per_fn_targets(solution_src) == [] -> :whole
      true -> :per_fn
    end
  end

  def base_mode(_solution_src, %Config{}), do: :whole

  @doc """
  The public functions a per-function raise-mutation sweep should target for `src`
  (a single-module solution): every `def` (name/arity), minus the ones `skip_fn?/2`
  exempts — `init/1` when `src` is a Plug (compile-time invoked; see `skip_fn?/2`)
  and `__foo__/n` compiler/seam functions. `[]` on a parse error or a module with no
  public defs (e.g. a test module). Shared by `gate_base/3` and the corpus per-fn
  mutation sweep (`scripts/validate.exs --per-fn-mutants`) so both apply one skip set.
  """
  @spec per_fn_targets(String.t()) :: [{atom(), non_neg_integer()}]
  def per_fn_targets(src) do
    plug? = plug_module?(src)
    src |> public_functions() |> Enum.reject(&skip_fn?(&1, plug?))
  end

  # Public functions the per-function gate must not require the harness to kill:
  #   * `init/1` — **in a Plug module only**: Plug invokes it at COMPILE time and inlines
  #     the result, so a gutted `init/1` raises *during compilation*; the mutant is
  #     inconclusive, not a kill. A GenServer's `init/1` holds real state-construction
  #     logic and IS mutated — the blanket exemption left GenServer startup semantics
  #     (options parsing, initial state, scheduling) unverified in a GenServer-heavy corpus.
  #   * `__foo__/n` — the leading-and-trailing double-underscore convention marks an
  #     internal / injected seam (e.g. a default clock deliberately overridden in every
  #     test via a `:clock` option), not public behavior a test is meant to exercise.
  # These survive raise-mutation for structural reasons, not because the harness is
  # vacuous — requiring their kill produces a false smell.
  defp skip_fn?({:init, 1}, plug?), do: plug?

  defp skip_fn?({name, _arity}, _plug?) do
    s = Atom.to_string(name)
    String.starts_with?(s, "__") and String.ends_with?(s, "__")
  end

  @doc false
  def plug_module?(src), do: Regex.match?(~r/^\s*(use|import)\s+Plug\b|Plug\.Builder/m, src)

  defp gate_base_whole(mutant_dir, files, cfg) do
    source = files["solution.ex"]
    mutated = mutate(source)

    if mutated == source do
      # `mutate/1` returns the source unchanged when the mutant cannot be built (parse
      # error, empty bundle). Grading that "mutant" would go green and be reported as
      # "tests still pass after every function body is replaced by raise" — a lie that
      # sends the fixer off to strengthen a harness that may be fine. Say what happened.
      {:survived,
       "a raise-mutant could not be constructed (mutation left the source unchanged — " <>
         "parse failure or empty bundle); coverage cannot be verified and no harness " <>
         "edit can fix this"}
    else
      gate_base_whole_graded(mutant_dir, files, mutated, cfg)
    end
  end

  defp gate_base_whole_graded(mutant_dir, files, mutated, cfg) do
    mutant_files = Map.put(files, "solution.ex", mutated)
    Evaluator.stage!(mutant_dir, mutant_files)
    grade = Evaluator.grade(mutant_dir, cfg)

    case fate(grade) do
      :killed ->
        Logger.debug("base mutation gate (whole-module): killed")
        :killed

      :survived ->
        Logger.debug("base mutation gate (whole-module): survived")
        {:survived, "the tests still pass after every function body is replaced by `raise`"}

      :inconclusive ->
        Logger.debug("base mutation gate (whole-module): inconclusive")

        {:survived,
         "the whole-module raise-mutant graded inconclusively (mutant compile failure " <>
           "or eval timeout) — coverage cannot be verified"}
    end
  end

  defp gate_base_per_fn(mutant_dir, files, fns, cfg) do
    Enum.reduce_while(fns, :killed, fn {name, arity}, _acc ->
      mutant_files = Map.put(files, "solution.ex", mutate_fn(files["solution.ex"], name, arity))
      Evaluator.stage!(mutant_dir, mutant_files)
      grade = Evaluator.grade(mutant_dir, cfg)

      case fate(grade) do
        :killed ->
          {:cont, :killed}

        :survived ->
          Logger.debug("base mutation gate (per-fn): #{name}/#{arity} survived")

          {:halt,
           {:survived,
            "the raise-mutant of `#{name}/#{arity}` still passes the tests — that public " <>
              "function is not exercised by test_harness.exs"}}

        :inconclusive ->
          Logger.debug("base mutation gate (per-fn): #{name}/#{arity} inconclusive")

          {:halt,
           {:survived,
            "the raise-mutant of `#{name}/#{arity}` graded inconclusively (mutant compile " <>
              "failure or eval timeout) — coverage cannot be verified"}}
      end
    end)
  end

  @doc """
  FIM gate. `fim_dir` is the `_0d` subtask dir; `candidate_src` is the candidate
  function. Writes a mutant of the candidate to `mutant_path` and grades `fim_dir`
  with it as the override solution. Returns `:killed` when the parent harness fails
  (target is covered), else `:survived`.
  """
  @spec gate_fim(String.t(), String.t(), String.t(), Config.t()) :: result()
  def gate_fim(fim_dir, candidate_src, mutant_path, %Config{} = cfg) do
    guard_not_tasks!(mutant_path)
    File.mkdir_p!(Path.dirname(mutant_path))
    # FIM candidate: keep `EvalTask.Fim.mutate/1` — it unwraps a fenced single
    # function via `extract_candidate/1`, which is correct here (and wrong for a
    # whole module, hence the distinct `mutate/1` above).
    File.write!(mutant_path, EvalTask.Fim.mutate(candidate_src))
    grade = Evaluator.grade(fim_dir, cfg, mutant_path)

    case fate(grade) do
      :killed ->
        Logger.debug("fim mutation gate: killed")
        :killed

      :survived ->
        Logger.debug("fim mutation gate: survived")
        {:survived, "the parent harness still passes with the candidate function gutted"}

      :inconclusive ->
        Logger.debug("fim mutation gate: inconclusive")

        {:survived,
         "the gutted-candidate mutant graded inconclusively (mutant compile failure " <>
           "or eval timeout) — coverage cannot be verified"}
    end
  end

  @doc """
  Test-FIM isolation gate. `iso_dir` is a staging dir; `module_src` is the parent
  reference module; `isolated_harness` is the harness reduced to the single target
  `test` block plus its helpers/`setup` (all other `test` blocks removed).

  Mutate each function of the module (`def` AND `defp`) to `raise` and run the isolated
  harness against it; the block is a valid tfim target iff it kills **≥1** mutant
  (proving it asserts real behavior, not just structure). Early-exits on the first kill.
  Returns `:killed` or `{:survived, reason}` (a vacuous block — reject the target).
  """
  @spec gate_isolation(String.t(), String.t(), String.t(), Config.t()) :: result()
  def gate_isolation(iso_dir, module_src, isolated_harness, %Config{} = cfg) do
    # Sanity: the isolated block must itself pass the real module. Otherwise it would
    # "fail" against every mutant too and be mistaken for a mutant-killer (false pass).
    Evaluator.stage!(iso_dir, %{
      "solution.ex" => module_src,
      "test_harness.exs" => isolated_harness
    })

    if not Evaluator.green?(Evaluator.grade(iso_dir, cfg)) do
      {:survived,
       "the isolated test block is not green against the reference module — it is not " <>
         "independent (depends on other tests) or is malformed"}
    else
      killed? =
        module_src
        |> all_functions()
        |> Enum.reduce_while(false, fn {kind, name, arity}, _acc ->
          mutant = mutate_fn(module_src, name, arity, kind)

          Evaluator.stage!(iso_dir, %{
            "solution.ex" => mutant,
            "test_harness.exs" => isolated_harness
          })

          # A kill needs positive evidence (the block RAN and failed); an
          # inconclusive grade (mutant compile failure / timeout) proves nothing,
          # so keep scanning the remaining functions.
          if Evaluator.killed_by_tests?(Evaluator.grade(iso_dir, cfg)),
            do: {:halt, true},
            else: {:cont, false}
        end)

      if killed? do
        :killed
      else
        {:survived,
         "the isolated test block kills no raise-mutant of the module — it asserts nothing " <>
           "about behavior"}
      end
    end
  end

  # A mutant's fate needs POSITIVE evidence in both directions (docs/05 #18):
  # :killed when the harness ran and failed (`killed_by_tests?`) — or ERRORED while
  # the mutant compiled (`errored_against_mutant?`): every gate in this module runs
  # only after the same harness graded green against the reference, so an error
  # appearing only against the mutant is caused by the mutation and is a kill
  # (docs/10 §5.1 — a gutted `defmacro` raises at harness COMPILE time; the 074
  # family). :survived only when it ran and passed (`green?`). Everything else —
  # the MUTANT failing to compile (e.g. staged without a tier-B manifest) or the
  # eval timing out — is :inconclusive: the harness never observed the mutated
  # behavior, so it must not count as coverage.
  defp fate(grade) do
    cond do
      Evaluator.killed_by_tests?(grade) -> :killed
      Evaluator.errored_against_mutant?(grade) -> :killed
      Evaluator.green?(grade) -> :survived
      true -> :inconclusive
    end
  end

  defp guard_not_tasks!(path) do
    normalized = Path.expand(path)
    tasks_root = Path.expand("tasks")

    if String.starts_with?(normalized, tasks_root <> "/") do
      raise ArgumentError, "refusing to write a mutant into tasks/: #{path}"
    end
  end
end
