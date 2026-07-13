# enrich_prompts.exs — make a terse seed prompt state what its module actually does.
#
# WHY (docs/13 §1.4): `strengthen_harnesses` could not tighten 12 families
# because every test it added pinned behavior the PROMPT never states — the
# blind gate rejected each one. The modules are fine; the prompts are 14–18
# lines of latitude. So the harness is not the weak link: the SPEC is. Order of
# operations is therefore: enrich the prompt → prove it is still blind-solvable
# → re-strengthen the harness (that last step is a separate tool).
#
# The model sees ONLY the current prompt + the reference module — never the
# harness. Writing a prompt against the tests is precisely the corruption the
# blind screen exists to prevent, so the tests are not shown and any leak is
# gated out below.
#
# GATES (a rewrite must pass ALL of them, else the prompt is left untouched):
#   1. no-leak       — no verbatim test name from the parent harness appears
#   2. no-giveaway   — no >=4-line verbatim block copied out of solution.ex
#                      (an enriched prompt must specify behavior, not hand over
#                      the implementation — which would trivially pass gate 5)
#   3. api-preserved — every public `name/arity` the module exposes and the old
#                      prompt named is still named; no invented functions
#   4. additive      — the rewrite is longer than the original (it documents
#                      MORE) and still names the module
#   5. BLIND SOLVE   — a solver reading ONLY the enriched prompt goes green
#                      against the EXISTING harness (the S6 property, docs/12)
#
# Applying cascades to every child that embeds the parent spec: wt_ prompts
# (resync_embeds --wt-all) and bugfix_ prompts (resync_bugfix_embeds); repair_
# prompts are captured evidence and stay frozen by design.
#
# AFTER a run, refresh the S6 ledger with the canonical screen — an enriched
# prompt has a new sha, so `logs/screen_blind.jsonl` no longer covers it, and
# the in-tool gate (though the same mechanism) is not the ledger of record:
#
#   mix run scripts/screen_blind_solve.exs --only "<fam1>,<fam2>,…"
#
# Then re-strengthen: the whole point is a harness that can finally pin the
# behavior the prompt now states (`scripts/strengthen_harnesses.exs -- --go`).
#
# Usage:
#   mix run scripts/enrich_prompts.exs                    # DRY: the work list
#   mix run scripts/enrich_prompts.exs -- --go            # PAID: ~2 calls/family
#   mix run scripts/enrich_prompts.exs -- --go --limit 2
#   mix run scripts/enrich_prompts.exs -- --only "013_002*"
#   mix run scripts/enrich_prompts.exs -- --report
#
# Ledger: logs/enrich_prompts.jsonl (one row per family per attempt; resume by
# prompt sha — an already-enriched prompt is skipped).

alias GenTask.{Config, Cycle, CycleLog, Evaluator, Reply, Variations}

defmodule EnrichPrompts do
  @moduledoc false

  @strengthen "logs/strengthen_harnesses.jsonl"
  @ledger "logs/enrich_prompts.jsonl"

  def main(argv) do
    argv = Enum.drop_while(argv, &(&1 == "--"))

    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [go: :boolean, report: :boolean, limit: :integer, only: :string, force: :boolean]
      )

    cond do
      opts[:report] -> report()
      opts[:go] -> go(opts)
      true -> dry(opts)
    end
  end

  # ── population: families the blind gate rejected ────────────────────────────

  defp population(opts) do
    from_ledger =
      case File.read(@strengthen) do
        {:ok, body} ->
          body
          |> String.split("\n", trim: true)
          |> Enum.map(&JSON.decode!/1)
          # ANY family the strengthener could not fix is a candidate: the blind-gate
          # rejections are the clearest case (a test pinned undocumented behavior),
          # but the same terse-spec weakness explains the others — the model reached
          # into internals because the prompt names no observable contract (S9), or
          # it wrote tests the reference fails because it had to guess semantics.
          # Policy: if the harness cannot be fixed, fix the SPEC first.
          |> Enum.filter(&(&1["verdict"] == "rejected"))
          |> Enum.map(& &1["family"])
          |> Enum.uniq()

        _ ->
          []
      end

    from_ledger
    |> Enum.filter(&match_only?(&1, opts[:only]))
    |> Enum.filter(&File.dir?(Path.join("tasks", &1)))
    |> Enum.sort()
  end

  defp dry(opts) do
    fams = population(opts)
    done = done_shas()

    IO.puts("Terse-prompt work list (blind-gate rejections from #{@strengthen}):\n")

    for f <- fams do
      dir = Path.join("tasks", f)
      lines = dir |> Path.join("prompt.md") |> File.read!() |> String.split("\n") |> length()

      status =
        if MapSet.member?(done, prompt_sha(dir)),
          do: "DONE (this prompt already enriched)",
          else: "todo"

      IO.puts("  #{String.pad_leading(to_string(lines), 3)} lines  #{f}  #{status}")
    end

    IO.puts("\n#{length(fams)} family(ies); ~2 LLM calls each. Run with `-- --go`.")
  end

  # ── the loop ────────────────────────────────────────────────────────────────

  defp go(opts) do
    refuse_if_generate_alive!()
    cfg = Config.new([])
    done = done_shas()

    todo =
      opts
      |> population()
      |> then(fn fams ->
        # --force re-enriches an already-enriched prompt (a first pass can land a
        # thin rewrite — 041_001's was 14->35 lines while its peers reached 60-110).
        if opts[:force],
          do: fams,
          else: Enum.reject(fams, &MapSet.member?(done, prompt_sha(Path.join("tasks", &1))))
      end)
      |> then(&if opts[:limit], do: Enum.take(&1, opts[:limit]), else: &1)

    IO.puts("enriching #{length(todo)} prompt(s), sequential, ledger #{@ledger}\n")

    Enum.each(Enum.with_index(todo, 1), fn {fam, i} ->
      IO.write("[#{i}/#{length(todo)}] #{fam} ... ")
      row = enrich(cfg, fam)
      append(row)
      IO.puts("#{row.verdict}#{if row[:detail], do: " — " <> row.detail, else: ""}")
    end)

    report()
  end

  defp enrich(cfg, fam) do
    dir = Path.join("tasks", fam)
    prompt0 = File.read!(Path.join(dir, "prompt.md"))
    solution = File.read!(Path.join(dir, "solution.ex"))
    harness = File.read!(Path.join(dir, "test_harness.exs"))
    manifest = read_optional(Path.join(dir, "manifest.exs"))

    base = %{
      family: fam,
      prompt_sha_before: CycleLog.content_sha(prompt0),
      lines_before: length(String.split(prompt0, "\n")),
      ts: now()
    }

    with {:ok, prompt1} <- generate(cfg, fam, prompt0, solution),
         :ok <- no_leak(prompt1, harness),
         :ok <- no_giveaway(prompt1, solution),
         :ok <- api_preserved(prompt0, prompt1, solution),
         :ok <- additive(prompt0, prompt1, solution),
         :ok <- blind_solve(cfg, fam, prompt1, harness, solution, manifest) do
      File.write!(Path.join(dir, "prompt.md"), prompt1)
      cascade(fam)

      Map.merge(base, %{
        verdict: :applied,
        prompt_sha_after: CycleLog.content_sha(prompt1),
        lines_after: length(String.split(prompt1, "\n"))
      })
    else
      {:error, why} -> Map.merge(base, %{verdict: :rejected, detail: why})
    end
  end

  # ── the call ────────────────────────────────────────────────────────────────

  defp generate(cfg, fam, prompt, solution) do
    system =
      "You are a senior Elixir engineer writing the SPECIFICATION for a coding task. " <>
        "You reply with ONLY a single <file path=\"prompt.md\">…</file> block containing " <>
        "the complete rewritten prompt in Markdown, nothing else."

    user = """
    Below is a task prompt and the reference module that was written to satisfy it.
    The prompt is too vague: it leaves real behavior unstated, so a solver reading
    only the prompt cannot know what the module is supposed to do in edge cases,
    and any test that pins those cases would be testing undocumented behavior.

    Rewrite the prompt so that it DOCUMENTS the behavior the reference module
    actually implements. Hard rules:

    - ADDITIVE: keep everything the current prompt already asks for, keep the same
      task, the same module name, and the same public API (same function names and
      arities). Do not invent new functions or new requirements.
    - Specify the BEHAVIOR, not the implementation: state the observable contract —
      return shapes (`{:ok, …}` / `{:error, …}` tuples and what each means), default
      option values, boundary/edge-case semantics (what happens at exactly the limit,
      on an empty input, on an unknown key, on a repeated call), ordering guarantees,
      and any state transitions a caller can observe.
    - Do NOT paste the implementation. No copied code blocks from the module. A
      solver must still have to write the code.
    - Do NOT mention tests, test names, or a test suite.
    - Keep the original register and formatting style (a task request in Markdown).

    === current prompt.md ===
    #{prompt}

    === reference solution.ex (the truth about the behavior) ===
    #{solution}
    """

    case Cycle.opus(cfg, fam, "enrich_prompt", system, user) do
      {:ok, text, _meta} ->
        case Reply.parse(text) do
          %{"prompt.md" => p} when is_binary(p) and p != "" ->
            {:ok, String.trim_trailing(p) <> "\n"}

          _ ->
            {:error, "reply carried no prompt.md block"}
        end

      {:error, reason} ->
        {:error, "enrich call failed: #{inspect(reason)}"}
    end
  end

  # ── gates ───────────────────────────────────────────────────────────────────

  defp no_leak(prompt, harness) do
    names =
      ~r/^\s*(?:test|property)\s+"((?:[^"\\]|\\.)*)"/m
      |> Regex.scan(harness, capture: :all_but_first)
      |> Enum.map(fn [n] -> n end)

    case Enum.filter(names, &String.contains?(prompt, &1)) do
      [] -> :ok
      leaked -> {:error, "leaks #{length(leaked)} verbatim test name(s): #{hd(leaked)}"}
    end
  end

  # No 4+ consecutive non-trivial lines of the module may appear verbatim: an
  # enriched prompt specifies behavior; it does not hand over the answer (which
  # would make the blind-solve gate vacuous).
  defp no_giveaway(prompt, solution) do
    sol_lines =
      solution
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#") or String.length(&1) < 8))

    p = prompt |> String.split("\n") |> Enum.map(&String.trim/1)

    run =
      sol_lines
      |> Enum.chunk_every(4, 1, :discard)
      |> Enum.find(fn chunk -> subsequence?(p, chunk) end)

    if run, do: {:error, "copies #{4} consecutive module lines verbatim (giveaway)"}, else: :ok
  end

  defp subsequence?(hay, needle) do
    n = length(needle)

    hay
    |> Enum.chunk_every(n, 1, :discard)
    |> Enum.any?(&(&1 == needle))
  end

  defp api_preserved(prompt0, prompt1, solution) do
    pubs = GenTask.Mutation.public_functions(solution) |> Enum.map(fn {n, _a} -> to_string(n) end)

    dropped =
      pubs
      |> Enum.filter(fn f -> mentions?(prompt0, f) and not mentions?(prompt1, f) end)

    if dropped == [],
      do: :ok,
      else: {:error, "drops documented function(s): #{Enum.join(dropped, ", ")}"}
  end

  defp mentions?(text, fun), do: Regex.match?(~r/#{Regex.escape(fun)}(?!\w)/, text)

  defp additive(prompt0, prompt1, solution) do
    mod =
      case Regex.run(~r/defmodule\s+([A-Za-z][\w.]*)/, solution) do
        [_, m] -> m |> String.split(".") |> List.last()
        _ -> nil
      end

    cond do
      String.length(prompt1) <= String.length(prompt0) ->
        {:error, "rewrite is not longer than the original (nothing documented)"}

      mod && not String.contains?(prompt1, mod) ->
        {:error, "rewrite never names the module #{mod}"}

      true ->
        :ok
    end
  end

  # The S6 property: a solver reading ONLY the enriched prompt must still go
  # green against the EXISTING harness. Proves the enrichment is consistent with
  # the reference behavior AND still solvable (not over-constrained).
  defp blind_solve(cfg, fam, prompt, harness, solution, manifest) do
    case Variations.blind_solution("enrich_blind_#{fam}", prompt, cfg) do
      {:ok, blind} ->
        files =
          %{"prompt.md" => prompt, "solution.ex" => blind, "test_harness.exs" => harness}
          |> then(&if manifest, do: Map.put(&1, "manifest.exs", manifest), else: &1)

        dir = Evaluator.stage!(Path.join(cfg.staging_dir, "enrich_#{fam}"), files)

        case Evaluator.grade(dir, cfg) do
          {:ok, json} ->
            if Evaluator.green?({:ok, json}) do
              :ok
            else
              failing =
                (json["test_failures"] || [])
                |> Enum.take(3)
                |> Enum.map_join("; ", & &1["test"])

              {:error,
               "enriched prompt still not blind-solvable (#{Cycle.reason_for({:ok, json})})" <>
                 if(failing == "", do: "", else: " — failing: " <> failing)}
            end

          :timeout_or_crash ->
            {:error, "blind grade timed out/crashed"}
        end
        |> tap(fn _ -> _ = solution end)

      {:error, reason} ->
        {:error, "blind solve call failed: #{inspect(reason)}"}
    end
  end

  # ── cascade + bookkeeping ───────────────────────────────────────────────────

  # Children that embed the parent SPEC must follow it (docs/13 §1.1): wt_ and
  # bugfix_. repair_ prompts are captured evidence of a past request — frozen.
  defp cascade(fam) do
    fam7 = String.slice(fam, 0, 7)
    cmd("mix", ["run", "scripts/resync_embeds.exs", "--", "--wt-all", "--apply"])
    cmd("mix", ["run", "scripts/resync_bugfix_embeds.exs", "--", "--only", fam7, "--apply"])
  end

  defp cmd(bin, args) do
    {out, status} = System.cmd(bin, args, stderr_to_stdout: true)
    if status != 0, do: IO.puts("\n  cascade WARNING (#{Enum.join(args, " ")}): #{out}")
    :ok
  end

  defp append(row) do
    File.mkdir_p!("logs")
    File.write!(@ledger, JSON.encode!(row) <> "\n", [:append])
  end

  defp done_shas do
    case File.read(@ledger) do
      {:ok, body} ->
        body
        |> String.split("\n", trim: true)
        |> Enum.reduce(MapSet.new(), fn line, acc ->
          case JSON.decode(line) do
            {:ok, %{"verdict" => "applied", "prompt_sha_after" => sha}} when is_binary(sha) ->
              MapSet.put(acc, sha)

            _ ->
              acc
          end
        end)

      _ ->
        MapSet.new()
    end
  end

  defp report do
    case File.read(@ledger) do
      {:ok, body} ->
        rows = body |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)
        freq = Enum.frequencies_by(rows, & &1["verdict"])
        IO.puts("\n=== ENRICH LEDGER (#{length(rows)} row(s)) === #{inspect(freq)}")

        for r <- rows do
          case r["verdict"] do
            "applied" ->
              IO.puts("  #{r["family"]}: #{r["lines_before"]} → #{r["lines_after"]} lines")

            _ ->
              IO.puts("  #{r["family"]}: REJECTED — #{String.slice(r["detail"] || "", 0, 110)}")
          end
        end

      _ ->
        IO.puts("no ledger yet")
    end
  end

  defp prompt_sha(dir), do: CycleLog.content_sha(File.read!(Path.join(dir, "prompt.md")))
  defp read_optional(p), do: if(File.regular?(p), do: File.read!(p))
  defp now, do: DateTime.utc_now() |> DateTime.to_iso8601()

  defp match_only?(_f, nil), do: true

  defp match_only?(f, globs) do
    globs
    |> String.split(",", trim: true)
    |> Enum.any?(fn g ->
      re = g |> String.trim() |> Regex.escape() |> String.replace("\\*", ".*")
      Regex.match?(~r/#{re}/, f)
    end)
  end

  defp refuse_if_generate_alive! do
    {out, _} = System.cmd("pgrep", ["-af", "beam.smp"], stderr_to_stdout: true)

    if String.contains?(out, "generate.exs") do
      IO.puts("REFUSING --go: a generation loop (generate.exs) is alive.")
      System.halt(1)
    end
  end
end

EnrichPrompts.main(System.argv())
