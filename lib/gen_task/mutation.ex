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
      else: mutate_module_src(solution_src)
  rescue
    _ -> solution_src
  end

  # Gut every `def/defp/defmacro(p)` body of a single module source to `raise`,
  # except compile-time-invoked callbacks (see `compile_time_callback?/1`).
  defp mutate_module_src(module_src) do
    module_src
    |> Code.string_to_quoted!()
    |> Macro.prewalk(&mutate_module_node/1)
    |> Macro.to_string()
  end

  defp mutate_module_node({d, m, [head, kw]})
       when d in [:def, :defp, :defmacro, :defmacrop] and is_list(kw) do
    if Keyword.has_key?(kw, :do) and not compile_time_callback?(head),
      do: {d, m, [head, [do: quote(do: raise("MUTATION"))]]},
      else: {d, m, [head, kw]}
  end

  defp mutate_module_node(node), do: blank_docs(node)

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
  # gate reads it as inconclusive rather than killed. Leave `init/1` intact: the tested
  # request logic lives in `call/2`/handlers, which are still gutted, so a genuine harness
  # is still killed. (A solution whose only real logic is `init/1` is vanishingly rare and
  # would merely be flagged vacuous — the safe direction.)
  defp compile_time_callback?(head), do: head_name_arity(head) == {:init, 1}

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
              do: mutate_module_src(body),
              else: body

          ~s(<file path="#{path}">\n#{new_body}\n</file>)
        end)
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
  defp head_name_arity({:when, _, [inner | _]}), do: head_name_arity(inner)

  defp head_name_arity({name, _, args}) when is_atom(name) and is_list(args),
    do: {name, length(args)}

  defp head_name_arity({name, _, nil}) when is_atom(name), do: {name, 0}
  defp head_name_arity(_), do: nil

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
  def gate_base(mutant_dir, files, %Config{per_fn_mutation: true} = cfg) do
    cond do
      # A bundle's public API spans several modules; `public_functions`/`mutate_fn`
      # are single-module only, so per-fn mutation cannot address it. `mutate/1`
      # gutting every lib module is the whole-solution coverage check for bundles.
      Bundle.bundle?(files["solution.ex"]) ->
        gate_base_whole(mutant_dir, files, cfg)

      true ->
        case files["solution.ex"] |> public_functions() |> Enum.reject(&skip_fn?/1) do
          [] -> gate_base_whole(mutant_dir, files, cfg)
          fns -> gate_base_per_fn(mutant_dir, files, fns, cfg)
        end
    end
  end

  def gate_base(mutant_dir, files, %Config{} = cfg) do
    gate_base_whole(mutant_dir, files, cfg)
  end

  # Public functions the per-function gate must not require the harness to kill:
  #   * `init/1` — Plug invokes it at COMPILE time and inlines the result, so a gutted
  #     `init/1` raises *during compilation*; the mutant is inconclusive, not a kill.
  #   * `__foo__/n` — the leading-and-trailing double-underscore convention marks an
  #     internal / injected seam (e.g. a default clock deliberately overridden in every
  #     test via a `:clock` option), not public behavior a test is meant to exercise.
  # Both survive raise-mutation for structural reasons, not because the harness is
  # vacuous — requiring their kill produces a false smell.
  defp skip_fn?({:init, 1}), do: true

  defp skip_fn?({name, _arity}) do
    s = Atom.to_string(name)
    String.starts_with?(s, "__") and String.ends_with?(s, "__")
  end

  defp gate_base_whole(mutant_dir, files, cfg) do
    mutant_files = Map.put(files, "solution.ex", mutate(files["solution.ex"]))
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
         "the whole-module raise-mutant graded inconclusively (mutant compile failure, " <>
           "harness load error, or eval timeout) — coverage cannot be verified"}
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
              "failure, harness load error, or eval timeout) — coverage cannot be verified"}}
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
         "the gutted-candidate mutant graded inconclusively (mutant compile failure, " <>
           "harness load error, or eval timeout) — coverage cannot be verified"}
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
  # :killed only when the harness ran and failed (`killed_by_tests?`), :survived
  # only when it ran and passed (`green?`). Everything else — the mutant failing
  # to compile, the harness failing to load against it, or the eval timing out —
  # is :inconclusive: the harness never observed the mutated behavior, so it must
  # not count as coverage.
  defp fate(grade) do
    cond do
      Evaluator.killed_by_tests?(grade) -> :killed
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
