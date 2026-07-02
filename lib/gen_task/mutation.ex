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

  alias GenTask.{Config, Evaluator}

  @type result :: :killed | :survived

  @doc """
  Produce a whole-module mutant of `solution_src` (every `def/defp/defmacro(p)`
  body → `raise`).

  Unlike `EvalTask.Fim.mutate/1` this does **not** run the FIM candidate
  extraction (`extract_candidate/1`) first: on a whole module that regex would grab
  the first column-0 ```` ```elixir ```` fence — commonly a `@moduledoc`/`@doc`
  example — and discard the entire module, yielding a non-compiling "mutant" that is
  always `:killed` and so silently defeats the gate. We mutate the raw source AST
  directly. On a rescue we return the source **unchanged** so the mutant grades
  green (`:survived`) and is flagged as a vacuous harness — a conservative outcome
  that never wrongly accepts.
  """
  @spec mutate(String.t()) :: String.t()
  def mutate(solution_src) do
    solution_src
    |> Code.string_to_quoted!()
    |> Macro.prewalk(fn
      {d, m, [head, kw]} when d in [:def, :defp, :defmacro, :defmacrop] and is_list(kw) ->
        if Keyword.has_key?(kw, :do),
          do: {d, m, [head, [do: quote(do: raise("MUTATION"))]]},
          else: {d, m, [head, kw]}

      other ->
        other
    end)
    |> Macro.to_string()
  rescue
    _ -> solution_src
  end

  @doc """
  Base/variation gate. `files` is the accepted triplet; `mutant_dir` is a staging
  directory (must be outside `tasks/`). Stages the mutant with the same harness and
  grades it. Returns `:killed` when the mutant fails (harness is genuine), else
  `:survived`.
  """
  @spec gate_base(String.t(), %{String.t() => String.t()}, Config.t()) :: result()
  def gate_base(mutant_dir, files, %Config{} = cfg) do
    mutant_files = Map.put(files, "solution.ex", mutate(files["solution.ex"]))
    Evaluator.stage!(mutant_dir, mutant_files)
    grade = Evaluator.grade(mutant_dir, cfg)
    verdict = if Evaluator.green?(grade), do: :survived, else: :killed
    Logger.debug("base mutation gate: #{verdict}")
    verdict
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
    verdict = if Evaluator.green?(grade), do: :survived, else: :killed
    Logger.debug("fim mutation gate: #{verdict}")
    verdict
  end

  defp guard_not_tasks!(path) do
    normalized = Path.expand(path)
    tasks_root = Path.expand("tasks")

    if String.starts_with?(normalized, tasks_root <> "/") do
      raise ArgumentError, "refusing to write a mutant into tasks/: #{path}"
    end
  end
end
