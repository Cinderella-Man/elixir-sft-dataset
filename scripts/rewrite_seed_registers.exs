# rewrite_seed_registers.exs — G3's LLM half: rewrite monotone SEED prompts
# (the ~300 roots opening "Write me an Elixir…") into varied rhetorical
# registers WITHOUT touching what they promise, then prove each rewrite with
# a mandatory blind re-screen before it lands.
#
# Contract per root (docs/20 §5 step 5; STATUS G3):
#
#   1. SCOPE — single-module `_01` roots whose prompt opens with a monotone
#      head ("Write me an Elixir" / "Implement an Elixir"). Multifile roots
#      and already-diverse prompts are skipped.
#   2. REWRITE — one `Cycle.generate` call. The target register is chosen
#      DETERMINISTICALLY from the root id (phash2 over @registers), so a
#      relaunch asks for the same register again. The instruction forbids
#      semantic drift: every promise, API name, number, and edge-case
#      sentence must survive; only voice/structure/framing change.
#   3. MACHINE VET — every backtick-quoted token and every number of the old
#      prompt must appear in the new one (cheap containment proof that no
#      contract atom was dropped); length must stay within [0.6, 1.8]× of the
#      original (a summary or an essay both fail).
#   4. BLIND RE-SCREEN — an independent solver must go GREEN from the
#      CANDIDATE prompt alone against the UNCHANGED harness (staged and
#      graded through the real evaluator, no repair). Red → the rewrite is
#      REJECTED and the old prompt stands untouched.
#   5. LAND + CASCADE — write prompt.md, append the screen row to
#      logs/screen_blind.jsonl (S6 freshness by construction, same entry
#      shape as screen_blind_solve.exs), then re-render every derivative
#      embed of the family through the standing resync tools.
#
# Ledger: logs/register_rewrites.jsonl, keyed by sha256(old prompt.md) — a
# root whose CURRENT prompt sha already has a row (landed or rejected) is
# skipped, so interrupted runs resume for free and a hand-edited prompt
# automatically re-qualifies.
#
#   mix run scripts/rewrite_seed_registers.exs -- --census        # no calls
#   mix run scripts/rewrite_seed_registers.exs -- --self-test     # no calls
#   mix run scripts/rewrite_seed_registers.exs -- --limit 3       # pilot
#   mix run scripts/rewrite_seed_registers.exs -- --only "080_*"
#   mix run scripts/rewrite_seed_registers.exs                    # full sweep
#
# LLM cost: 2 calls per root (rewrite + blind solve). Run DETACHED
# (scripts/run_detached.sh) — the transport rides usage windows by sleeping.

alias GenTask.{Config, Cycle, CycleLog, Evaluator, Prompts, Reply}

defmodule RewriteSeedRegisters do
  @moduledoc false

  @ledger "register_rewrites.jsonl"
  @screen_ledger "screen_blind.jsonl"
  @monotone_heads ["Write me an Elixir", "Implement an Elixir"]

  # Target registers, selected per root by phash2 — the SAME axis the
  # generator's base_task meta-prompt instructs for fresh mints.
  @registers [
    "a titled specification document with section headings (## Overview, ## API, " <>
      "## Edge cases — names of your choosing), written in third person",
    "a maintainer's change request: a colleague describes the module they need in " <>
      "first person, conversational but precise, no headings",
    "a design brief: states the problem and constraints first, then the required " <>
      "interface as a numbered list, closing with acceptance criteria",
    "a terse engineering ticket: summary line, then requirement bullets grouped " <>
      "under bold lead-ins, no fluff"
  ]

  def main(argv) do
    argv = Enum.drop_while(argv, &(&1 == "--"))

    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [census: :boolean, limit: :integer, only: :string, self_test: :boolean]
      )

    if opts[:self_test] do
      self_test()
      System.halt(0)
    end

    cfg = Config.new([])
    roots = candidates(cfg, opts[:only])

    if opts[:census] do
      IO.puts("register-rewrite candidates: #{length(roots)}")
      for r <- roots, do: IO.puts("  #{Path.basename(r)}")
      System.halt(0)
    end

    roots = if opts[:limit], do: Enum.take(roots, opts[:limit]), else: roots
    IO.puts("register rewrite: #{length(roots)} root(s), sequential, 2 calls each")

    freq =
      roots
      |> Enum.with_index(1)
      |> Enum.map(fn {dir, i} ->
        IO.write("[#{i}/#{length(roots)}] #{Path.basename(dir)} ... ")
        outcome = rewrite_root(dir, cfg)
        IO.puts(outcome)
        outcome
      end)
      |> Enum.frequencies()

    IO.puts("register rewrite done: #{inspect(freq)}")
    if freq[:error], do: System.halt(1)
  end

  # ── scope ──────────────────────────────────────────────────────────────────

  @doc false
  def candidates(cfg, only_glob) do
    Path.wildcard(Path.join(cfg.tasks_dir, "[0-9]*_01"))
    |> Enum.filter(&File.dir?/1)
    |> Enum.filter(&match_only?(Path.basename(&1), only_glob))
    |> Enum.filter(fn dir ->
      with {:ok, p} <- File.read(Path.join(dir, "prompt.md")),
           {:ok, sol} <- File.read(Path.join(dir, "solution.ex")) do
        monotone?(p) and File.regular?(Path.join(dir, "test_harness.exs")) and
          not EvalTask.Bundle.bundle?(sol) and not ledgered?(cfg, p)
      else
        _ -> false
      end
    end)
    |> Enum.sort()
  end

  @doc false
  def monotone?(prompt) do
    head = prompt |> String.split("\n", parts: 2) |> hd()
    Enum.any?(@monotone_heads, &String.starts_with?(head, &1))
  end

  # ── the per-root pipeline ──────────────────────────────────────────────────

  defp rewrite_root(dir, cfg) do
    id = Path.basename(dir)
    old_prompt = File.read!(Path.join(dir, "prompt.md"))
    harness = File.read!(Path.join(dir, "test_harness.exs"))
    register = Enum.at(@registers, :erlang.phash2(id, length(@registers)))

    with {:ok, candidate} <- ask_rewrite(id, old_prompt, register, cfg),
         :ok <- vet(old_prompt, candidate),
         {:ok, screen} <- blind_screen(dir, candidate, harness, cfg) do
      land(dir, id, old_prompt, candidate, register, screen, cfg)
      :landed
    else
      {:rejected, why} ->
        record(cfg, id, old_prompt, nil, register, "rejected", why)
        :rejected

      {:error, why} ->
        IO.write("(#{inspect(why)}) ")
        :error
    end
  end

  defp ask_rewrite(id, old_prompt, register, cfg) do
    system =
      "You rewrite task prompts for an Elixir SFT dataset. You change ONLY the " <>
        "rhetorical register — never the contract."

    user = """
    Rewrite the task prompt below into a different rhetorical register:
    #{register}.

    HARD RULES — the rewrite is machine-checked and then blind-solved against
    the task's real test suite, so:
    - every behavioral promise, edge case, default, and constraint must
      survive with its meaning intact (reordering and rephrasing are fine);
    - every backtick-quoted identifier (`Module.fun/arity`, option names,
      atoms, code snippets) and every numeric value must appear verbatim;
    - do not add new requirements, hints, or examples the original lacks;
    - do not shorten it into a summary — carry ALL the content.

    Task id: #{id}

    === ORIGINAL PROMPT ===
    #{old_prompt}

    Return the rewritten prompt as ONE file block, exactly:

    <file path="prompt.md">
    …the complete rewritten prompt…
    </file>
    """

    validator = fn files ->
      case files["prompt.md"] do
        body when is_binary(body) and body != "" -> :ok
        _ -> {:error, "reply must contain a non-empty <file path=\"prompt.md\"> block"}
      end
    end

    case Cycle.generate(cfg, id, "register_rewrite", system, user, validator) do
      {:ok, files} -> {:ok, String.trim_trailing(files["prompt.md"]) <> "\n"}
      {:error, reason} -> {:error, reason}
    end
  end

  # Cheap containment proof: no contract atom may vanish. The blind screen is
  # the real gate; this catches drops before paying for the solve.
  @doc false
  def vet(old_prompt, candidate) do
    missing_ticks =
      old_prompt
      |> tokens(~r/`([^`\n]+)`/)
      |> Enum.reject(&String.contains?(candidate, &1))

    missing_numbers =
      old_prompt
      |> tokens(~r/(?<![\w.])(\d[\d_]*)(?![\w.])/)
      |> Enum.reject(&String.contains?(candidate, &1))

    ratio = String.length(candidate) / max(String.length(old_prompt), 1)

    cond do
      missing_ticks != [] ->
        {:rejected, "dropped backticked token(s): #{Enum.join(Enum.take(missing_ticks, 5), ", ")}"}

      missing_numbers != [] ->
        {:rejected, "dropped number(s): #{Enum.join(Enum.take(missing_numbers, 5), ", ")}"}

      ratio < 0.6 ->
        {:rejected, "rewrite too short (#{Float.round(ratio, 2)}x)"}

      ratio > 1.8 ->
        {:rejected, "rewrite too long (#{Float.round(ratio, 2)}x)"}

      true ->
        :ok
    end
  end

  defp tokens(text, re) do
    re |> Regex.scan(text, capture: :all_but_first) |> List.flatten() |> Enum.uniq()
  end

  # One blind solve of the CANDIDATE prompt against the UNCHANGED harness —
  # the screen_blind_solve contract (no repair loop), graded via the real
  # evaluator in a staging dir.
  defp blind_screen(dir, candidate, harness, cfg) do
    id = Path.basename(dir)
    {system, user} = Prompts.base_solve(candidate)

    case Cycle.generate(cfg, id, "register_screen", system, user, &Reply.validate_answer/1) do
      {:error, reason} ->
        {:error, {:screen_transport, reason}}

      {:ok, answer} ->
        stage = Path.join(cfg.staging_dir, "register_screen_#{id}")

        Evaluator.stage!(stage, %{
          "prompt.md" => candidate,
          "solution.ex" => answer["solution.ex"],
          "test_harness.exs" => harness
        })

        grade = Evaluator.grade(stage, cfg)

        if Evaluator.green?(grade),
          do: {:ok, Cycle.grade_stats(grade)},
          else: {:rejected, "blind re-screen RED: " <> Cycle.reason_for(grade)}
    end
  end

  defp land(dir, id, old_prompt, candidate, register, screen, cfg) do
    File.write!(Path.join(dir, "prompt.md"), candidate)

    # S6 by construction: the landing verdict IS a fresh green blind row for
    # the new prompt sha — same (prompt, harness)-pair keying as
    # screen_blind_solve.exs writes.
    append_jsonl(cfg, @screen_ledger, %{
      ts: DateTime.utc_now() |> DateTime.to_iso8601(),
      task: id,
      sha: CycleLog.content_sha(candidate),
      harness_sha: CycleLog.content_sha(File.read!(Path.join(dir, "test_harness.exs"))),
      green: true,
      model: cfg.model,
      via: "register_rewrite",
      tests_passed: screen.tests_passed,
      tests_total: screen.tests_total
    })

    record(cfg, id, old_prompt, candidate, register, "landed", nil)
    cascade(id)
  end

  # Re-render every derivative embed of the family through the standing
  # resync tools. Each is idempotent and scoped; failures surface loudly.
  defp cascade(id) do
    family = String.replace_suffix(id, "_01", "")

    for script <- [
          "resync_bugfix_embeds.exs",
          "resync_tfim_embeds.exs",
          "resync_adapt_embeds.exs",
          "resync_dedoc_embeds.exs",
          "resync_tdd_embeds.exs",
          "resync_sfim_specs.exs",
          "resync_specfim_embeds.exs",
          "resync_bundlefim_embeds.exs"
        ] do
      {out, status} =
        System.cmd("mix", ["run", "scripts/#{script}", "--", "--only", "*#{family}*", "--apply"],
          stderr_to_stdout: true
        )

      if status != 0 do
        IO.write("[cascade #{script} rc=#{status}: #{String.slice(out, -200..-1//1)}] ")
      end
    end

    # wt_ prompts embed the parent spec too; --wt-all is the tool's only mode.
    {_, _} =
      System.cmd("mix", ["run", "scripts/resync_embeds.exs", "--", "--wt-all", "--apply"],
        stderr_to_stdout: true
      )

    :ok
  end

  # ── ledgers ────────────────────────────────────────────────────────────────

  defp ledgered?(cfg, old_prompt) do
    sha = CycleLog.content_sha(old_prompt)

    case File.read(Path.join(cfg.logs_dir, @ledger)) do
      {:ok, body} -> String.contains?(body, sha)
      _ -> false
    end
  end

  defp record(cfg, id, old_prompt, candidate, register, verdict, why) do
    append_jsonl(cfg, @ledger, %{
      ts: DateTime.utc_now() |> DateTime.to_iso8601(),
      task: id,
      old_sha: CycleLog.content_sha(old_prompt),
      new_sha: candidate && CycleLog.content_sha(candidate),
      register: register,
      verdict: verdict,
      why: why
    })
  end

  defp append_jsonl(cfg, name, map) do
    File.mkdir_p!(cfg.logs_dir)
    File.write!(Path.join(cfg.logs_dir, name), Jason.encode!(map) <> "\n", [:append])
  end

  defp match_only?(_name, nil), do: true

  defp match_only?(name, globs) do
    globs
    |> String.split(",", trim: true)
    |> Enum.any?(fn g ->
      re = g |> String.trim() |> Regex.escape() |> String.replace("\\*", ".*")
      Regex.match?(~r/#{re}/, name)
    end)
  end

  # ── self-test (no LLM): scope + vet bite both ways ─────────────────────────

  defp self_test do
    checks = [
      {"a monotone head is in scope", monotone?("Write me an Elixir module called `X`.\n")},
      {"a titled prompt is out of scope", not monotone?("# Sliding window\n\nBuild…")},
      {"vet passes a faithful reorder",
       vet("Use `Foo.bar/2` with 500 ms.", "With 500 ms, call `Foo.bar/2`.") == :ok},
      {"vet catches a dropped identifier",
       match?({:rejected, _}, vet("Use `Foo.bar/2` now.", "Use it now."))},
      {"vet catches a dropped number",
       match?({:rejected, _}, vet("wait 250 ms then 500 ms", "wait 250 ms plus a bit"))},
      {"vet catches a summary",
       match?(
         {:rejected, "rewrite too short" <> _},
         vet(String.duplicate("all the contract text here ", 40), "short")
       )}
    ]

    for {label, ok?} <- checks,
        do: IO.puts("  #{if ok?, do: "caught ✓", else: "MISSED ✗"}  #{label}")

    unless Enum.all?(checks, &elem(&1, 1)) do
      IO.puts("register-rewrite SELF-TEST FAILED")
      System.halt(1)
    end

    IO.puts("register-rewrite self-test: OK ✓ (#{length(checks)} checks)")
  end
end

unless System.get_env("SCRIPTS_NO_AUTORUN"), do: RewriteSeedRegisters.main(System.argv())
