# dialyzer_golds.exs — Dialyzer sweep over the gold solutions (T1.6, docs/13 §2.6).
#
# WHY: 019_001 shipped a @spec contradicting its own code; 038_001's build/2
# @spec omitted the `{:error, {:duplicate_ids, _}}` return its code produces;
# 043_001 declared `:ets.tid()` for a named-table atom. Specs are training
# targets (and the hard prerequisite for the dedoc shape, docs/13 §2.3) — they
# must be machine-checked, not trusted.
#
# The ANALYSIS (staging, the calibrated `:overspecs` filter, waivers, ledger
# keys) lives in `GenTask.Dialyzer` — ONE implementation shared with the
# ACCEPT-PATH gate wired into `GenTask.Cycle` (docs/12 §5.5 rows 15+23,
# 2026-07-19). This script is the retro/full-sweep driver over `tasks/`; its
# --self-test is the bite-proof for the shared implementation (planted public
# lie + public overspec must flag; private narrow helper, GenServer.call
# wrapper and a clean module must stay silent).
#
# LEDGER (CONTEXT.md rule 2): every analyzed root gets a JSONL row in
# logs/dialyzer_golds.jsonl keyed by content sha + gate sha (the
# GenTask.Dialyzer beam + the PLT hash) — a relaunch skips finished work;
# editing the gate module or rebuilding the PLT auto-invalidates old verdicts
# (rule-7 corollary). `error` rows are always retried.
#
# USAGE:
#   mix run scripts/dialyzer_golds.exs                        # full pass
#   mix run scripts/dialyzer_golds.exs -- --only "038*,043*"  # subset
#   mix run scripts/dialyzer_golds.exs -- --self-test         # prove the gate bites
#   flags: --tasks <dir> --ledger <path> --plt <path> (defaults: tasks/,
#          logs/dialyzer_golds.jsonl, the _build/dev dialyxir deps PLT)
#
# EXIT: 0 when every root analyzed THIS RUN is clean; 1 when any run produced
# warnings/error rows (the weekly CI gate keys off this); 2 on setup problems.

alias GenTask.Dialyzer

defmodule DialyzerGolds do
  # Self-test plants: each is {name, source, expectation}.
  @self_tests [
    {"lie_public_contract",
     """
     defmodule DialyzerGoldsSelfTest.Lie do
       @spec add(integer(), integer()) :: atom()
       def add(a, b), do: a + b
     end
     """, :flagged},
    {"overspec_public_return",
     """
     defmodule DialyzerGoldsSelfTest.Overspec do
       @spec fetch(map(), term()) :: {:ok, term()}
       def fetch(m, k) do
         case m do
           %{^k => v} -> {:ok, v}
           _ -> {:error, :not_found}
         end
       end
     end
     """, :flagged},
    {"private_narrow_helper",
     """
     defmodule DialyzerGoldsSelfTest.PrivateNarrow do
       @spec run(list()) :: non_neg_integer()
       def run(items), do: count(items)

       # Arg spec intentionally narrower than the success typing
       # (maybe_improper_list()) — the overspecs class this gate must NOT flag.
       @spec count([map()]) :: non_neg_integer()
       defp count(items), do: length(items)
     end
     """, :silent},
    {"genserver_call_wrapper",
     """
     defmodule DialyzerGoldsSelfTest.CallWrapper do
       # GenServer.call's success typing returns any(): comparing a reply spec
       # against it carries zero information, and this OTP-heavy corpus is full
       # of client wrappers — the gate must NOT flag them.
       @spec get(GenServer.server(), term()) :: {:ok, term()} | :miss
       def get(server, key), do: GenServer.call(server, {:get, key})
     end
     """, :silent},
    {"clean_public",
     """
     defmodule DialyzerGoldsSelfTest.Clean do
       @spec add(integer(), integer()) :: integer()
       def add(a, b) when is_integer(a) and is_integer(b), do: a + b
     end
     """, :silent}
  ]

  def main(argv) do
    # `mix run script.exs -- --self-test` leaves the literal `--` in System.argv,
    # and OptionParser treats it as an end-of-options terminator — silently turning
    # a --self-test invocation into a full sweep (bit live, 2026-07-16). Same
    # idiom as resync_tfim_embeds.exs: drop a leading `--`.
    argv = Enum.drop_while(argv, &(&1 == "--"))

    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [
          only: :string,
          tasks: :string,
          ledger: :string,
          plt: :string,
          self_test: :boolean
        ]
      )

    plt =
      opts[:plt] || Dialyzer.default_plt() ||
        halt_setup("no dialyxir deps PLT found — run: mix dialyzer --plt")

    File.regular?(plt) || halt_setup("PLT not a file: #{plt}")
    Code.compiler_options(ignore_module_conflict: true)

    if opts[:self_test] do
      self_test(plt)
    else
      run(opts[:tasks] || "tasks", opts[:ledger] || "logs/dialyzer_golds.jsonl", plt, opts[:only])
    end
  end

  # ── self-test: the gate must BITE (public contract lie + public overspec
  # return) and must NOT cry wolf (private narrow helper + clean module) ──────
  defp self_test(plt) do
    flag_n = Enum.count(@self_tests, &(elem(&1, 2) == :flagged))

    IO.puts(
      "self-test: #{length(@self_tests)} planted modules " <>
        "(#{flag_n} must flag, #{length(@self_tests) - flag_n} must stay silent)"
    )

    failures =
      for {name, source, expect} <- @self_tests,
          {outcome, detail} = Dialyzer.analyze_source(name, source, plt),
          verdict = if(outcome == :warnings, do: :flagged, else: :silent),
          verdict != expect or outcome == :error do
        "#{name}: expected #{expect}, got #{outcome} — #{first_line(detail)}"
      end

    if failures == [] do
      IO.puts(
        "self-test OK — public lie + public overspec flagged; private narrow helper + clean module silent"
      )

      System.halt(0)
    else
      Enum.each(failures, &IO.puts("self-test FAILED: #{&1}"))
      System.halt(2)
    end
  end

  # ── the sweep ───────────────────────────────────────────────────────────────
  defp run(tasks_dir, ledger, plt, only) do
    gate = Dialyzer.gate_sha(plt)
    done = Dialyzer.done_keys(ledger)

    roots =
      "#{tasks_dir}/*_01"
      |> Path.wildcard()
      |> Enum.filter(&File.dir?/1)
      |> Enum.filter(fn dir ->
        base = Path.basename(dir)

        match?({_, ""}, Integer.parse(hd(String.split(base, "_")))) and
          (only == nil or matches_only?(base, only))
      end)
      |> Enum.sort()

    {todo, done_n, bundle_n} =
      Enum.reduce(roots, {[], 0, 0}, fn dir, {todo, done_n, bundle_n} ->
        sol = Path.join(dir, "solution.ex")

        cond do
          not File.regular?(sol) ->
            {todo, done_n, bundle_n}

          EvalTask.Bundle.bundle?(File.read!(sol)) ->
            {todo, done_n, bundle_n + 1}

          MapSet.member?(done, Dialyzer.row_key(File.read!(sol), gate)) ->
            {todo, done_n + 1, bundle_n}

          true ->
            {[dir | todo], done_n, bundle_n}
        end
      end)

    todo = Enum.reverse(todo)

    IO.puts(
      "dialyzer golds: #{length(roots)} root(s) — #{length(todo)} to analyze, " <>
        "#{done_n} already analyzed at this content+gate, #{bundle_n} bundle-skipped " <>
        "(kit-tier staging is v2 — same scope as the retro audit) (PLT #{Path.basename(plt)})"
    )

    counts =
      todo
      |> Enum.with_index(1)
      |> Enum.reduce(%{clean: 0, warnings: 0, error: 0, waived: 0}, fn {dir, i}, acc ->
        base = Path.basename(dir)
        source = File.read!(Path.join(dir, "solution.ex"))

        {outcome, detail} =
          Dialyzer.analyze_source(base, source, plt, Dialyzer.harness_modules(dir))

        {outcome, detail} = Dialyzer.apply_waiver(outcome, detail, base, source)

        Dialyzer.append_row(ledger, %{
          ts: DateTime.utc_now() |> DateTime.to_iso8601(),
          task: base,
          key: Dialyzer.row_key(source, gate),
          gate_sha: gate,
          outcome: outcome,
          detail: String.slice(detail, 0, 4000)
        })

        IO.puts(
          "  [#{i}/#{length(todo)}] #{base} ... #{outcome}" <> outcome_note(outcome, detail)
        )

        Map.update!(acc, outcome, &(&1 + 1))
      end)

    IO.puts(
      "\ndone: #{counts.clean} clean, #{counts.warnings} with warnings, " <>
        "#{counts.waived} waived (see scripts/dialyzer_waivers.jsonl), #{counts.error} errors"
    )

    if counts.warnings > 0,
      do:
        IO.puts("""
        WARNINGS ARE FINDINGS (CONTEXT.md rule 7): each flagged root needs
          Task A — fix the gold's spec/code (defer while a corpus sweep is writing golds;
                   remember the bugfix/wt/tfim cascade + remints on solution edits), AND
          Task B — this gate stands at ACCEPT (GenTask.Cycle) and as the weekly sweep;
                   done when the pass reads all-clean.
        Rows: #{ledger} (jq 'select(.outcome=="warnings")').
        """)

    System.halt(if(counts.warnings + counts.error > 0, do: 1, else: 0))
  end

  defp matches_only?(name, patterns) do
    patterns
    |> String.split(",", trim: true)
    |> Enum.any?(fn glob ->
      Regex.match?(~r/\A#{glob |> Regex.escape() |> String.replace("\\*", ".*")}\z/, name)
    end)
  end

  defp outcome_note(:warnings, detail), do: " — #{first_line(detail)}"
  defp outcome_note(:error, detail), do: " — #{first_line(detail)}"
  defp outcome_note(_, _), do: ""

  defp first_line(text),
    do: text |> String.split("\n", trim: true) |> List.first() |> Kernel.||("")

  defp halt_setup(msg) do
    IO.puts("setup: #{msg}")
    System.halt(2)
  end
end

DialyzerGolds.main(System.argv())
