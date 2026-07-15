# retro_audit.exs — the ACCEPT-TIME promise audit, run RETROACTIVELY over roots
# that already exist (T1.11b, docs/17 §7 / Kamil 2026-07-15: "when the accept path
# gets stronger, existing data must not silently sit below it").
#
# For each base/variation `_01` root, this runs the SAME machinery a new accept
# gets (`GenTask.PromiseAudit`): one auditor call proposes prompt-anchored tests;
# each is machine-vetted (anchor → gold → bite); passing tests GROW the harness,
# failing tests machine-prove a gold defect and force a repair through the full
# shared cycle. A changed root is then BLIND-VERIFIED (one independent prompt-only
# solve must pass the grown harness — the S6 evidence row is appended in the
# screen ledger's schema so the freshness gate stays green) and only then written
# back to `tasks/`, with every replaced file backed up first. Child embeds are NOT
# cascaded here — run the standing resync gates afterwards (the run summary names
# the exact commands when needed).
#
# Ledger: logs/retro_audit.jsonl — one row per root per content+gate sha, so a
# relaunch resumes exactly where it stopped and a repaired gate re-opens old
# verdicts (HOW-WE-WORK rules 2 and 7).
#
#   mix run scripts/retro_audit.exs -- --limit 3            # PILOT (rule 9)
#   mix run scripts/retro_audit.exs -- --only "016_*"       # scope by glob
#   mix run scripts/retro_audit.exs                          # full sweep, resumable
#   mix run scripts/retro_audit.exs -- --dry-run             # plan only, no calls
#
# Skips: bundle roots (audit v1 is single-module), Postgres-tier roots (manifest
# db: :postgres — not gradable unattended). A transport/environmental failure
# errors the ROW (no verdict, the F7 rule) and the root is retried next run.

alias GenTask.{Config, CycleLog, Evaluator, PromiseAudit}

defmodule RetroAudit do
  @moduledoc false

  @ledger "retro_audit.jsonl"
  @backup_root "logs/retro_audit_backup"

  def main(argv) do
    argv = Enum.drop_while(argv, &(&1 == "--"))

    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [limit: :integer, only: :string, dry_run: :boolean, self_test: :boolean]
      )

    if opts[:self_test], do: self_test()

    cfg = %Config{Config.new([]) | promise_audit: true}
    roots = roots(cfg, opts[:only])
    done = ledger_keys(cfg)

    {todo, skipped} =
      roots
      |> Enum.map(&classify(&1, cfg, done))
      |> Enum.split_with(&(elem(&1, 0) == :todo))

    todo = if opts[:limit], do: Enum.take(todo, opts[:limit]), else: todo

    IO.puts(
      "retro audit: #{length(roots)} root(s) — #{length(todo)} to audit, " <>
        "#{Enum.count(skipped, &(elem(&1, 0) == :done))} already audited at this " <>
        "content+gate, #{Enum.count(skipped, &(elem(&1, 0) == :bundle))} bundle-skipped, " <>
        "#{Enum.count(skipped, &(elem(&1, 0) == :postgres))} postgres-skipped" <>
        if(opts[:dry_run], do: " [DRY-RUN]", else: "")
    )

    if opts[:dry_run] do
      Enum.each(todo, fn {:todo, dir, _files, _key} -> IO.puts("  would audit: #{dir}") end)
    else
      results =
        Enum.map(todo, fn {:todo, dir, files, key} -> audit_root(dir, files, key, cfg) end)

      summary = Enum.frequencies(results)
      IO.puts("\nretro audit summary: #{inspect(summary)}")

      if Enum.any?(results, &(&1 == :changed)) do
        IO.puts("""
        CHANGED roots need their child embeds cascaded — run:
          mix run scripts/resync_embeds.exs -- --wt-all --apply
          mix run scripts/resync_bugfix_embeds.exs -- --apply
          mix run scripts/resync_tfim_embeds.exs -- --apply
          mix run scripts/resync_adapt_embeds.exs -- --apply
          elixir scripts/check_embeds.exs   # then hand-fix any fix_child_gold rows
        and re-run scripts/audit_bugfix.exs on any family whose SOLUTION changed
        (a redesigned gold invalidates its bugfix pairs — delete + remint those).
        """)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Enumeration + resume
  # ---------------------------------------------------------------------------

  defp roots(cfg, only) do
    "#{cfg.tasks_dir}/*_01"
    |> Path.wildcard()
    |> Enum.filter(&File.dir?/1)
    |> Enum.filter(fn dir ->
      base = Path.basename(dir)
      parts = String.split(base, "_")

      match?({_n, ""}, Integer.parse(hd(parts))) and
        (only == nil or matches_only?(base, only))
    end)
    |> Enum.sort()
  end

  defp matches_only?(name, patterns) do
    patterns
    |> String.split(",", trim: true)
    |> Enum.any?(fn glob ->
      Regex.match?(~r/\A#{glob |> Regex.escape() |> String.replace("\\*", ".*")}\z/, name)
    end)
  end

  defp classify(dir, _cfg, done) do
    files =
      for f <- ["prompt.md", "solution.ex", "test_harness.exs"],
          path = Path.join(dir, f),
          File.regular?(path),
          into: %{},
          do: {f, File.read!(path)}

    manifest = Path.join(dir, "manifest.exs")

    cond do
      map_size(files) < 3 ->
        {:incomplete, dir}

      File.regular?(manifest) and File.read!(manifest) =~ ~r/db:\s*:postgres/ ->
        {:postgres, dir}

      EvalTask.Bundle.bundle?(files["solution.ex"]) ->
        {:bundle, dir}

      MapSet.member?(done, row_key(files)) ->
        {:done, dir}

      true ->
        {:todo, dir, files, row_key(files)}
    end
  end

  # The resume/invalidation key: content shas + the shas of the gate code that
  # judged them (rule-7 corollary: a repaired gate re-opens its old verdicts).
  defp row_key(files) do
    CycleLog.content_sha(files["prompt.md"] <> files["solution.ex"] <> files["test_harness.exs"]) <>
      ":" <> gate_sha()
  end

  defp gate_sha,
    do: CycleLog.gate_sha([PromiseAudit, GenTask.Mutation, GenTask.Evaluator, GenTask.Prompts])

  defp ledger_keys(cfg) do
    path = Path.join(cfg.logs_dir, @ledger)

    if File.regular?(path) do
      path
      |> File.stream!()
      |> Enum.flat_map(fn line ->
        case Jason.decode(line) do
          {:ok, %{"key" => key, "outcome" => o}} when o != "error" -> [key]
          _ -> []
        end
      end)
      |> MapSet.new()
    else
      MapSet.new()
    end
  end

  # ---------------------------------------------------------------------------
  # Per-root audit (the accept-path machinery, verbatim)
  # ---------------------------------------------------------------------------

  defp audit_root(dir, files, key, cfg) do
    id = Path.basename(dir)
    shape = if String.split(id, "_") |> Enum.at(1) == "001", do: :base, else: :variation
    IO.puts("\n=== #{id} (#{shape})")

    stage = Path.join(cfg.staging_dir, "retro_" <> id)
    Evaluator.stage!(stage, files)
    grade = Evaluator.grade(stage, cfg)

    if not Evaluator.green?(grade) do
      # Corpus rot is NOT this tool's job — surface loudly, never "repair" here.
      record(cfg, id, key, "error", "root not green against its own harness — investigate")
      :error
    else
      result = %{
        status: :accepted,
        files: files,
        grade: grade,
        attempts: 1,
        mutant_failed: true,
        mutation: nil,
        reason: nil
      }

      case PromiseAudit.run(result, id, shape, cfg) do
        {:ok, %{files: new_files}} when new_files == files ->
          record(cfg, id, key, "clean", "audit kept nothing — already covers its prompt")
          :clean

        {:ok, %{files: new_files}} ->
          verify_and_write(dir, id, key, files, new_files, cfg)

        {:rejected, why, _result} ->
          # The audit machine-proved a defect the repair loop could NOT close —
          # a human decision is required; the root is untouched.
          record(cfg, id, key, "needs_triage", why)
          :needs_triage

        {:error, reason} ->
          record(cfg, id, key, "error", inspect(reason))
          :error
      end
    end
  end

  # A grown/repaired root must carry fresh blind evidence before it lands on disk:
  # one independent prompt-only solve vs the NEW harness (the same S6 mechanism the
  # loop uses; the row keeps the freshness gate green for the changed bytes).
  defp verify_and_write(dir, id, key, old_files, new_files, cfg) do
    case GenTask.Variations.blind_solution(id, new_files["prompt.md"], cfg, "retro_audit_blind") do
      {:ok, blind_src} ->
        stage = Path.join(cfg.staging_dir, "retro_" <> id <> "_blind")
        Evaluator.stage!(stage, Map.put(new_files, "solution.ex", blind_src))
        blind_grade = Evaluator.grade(stage, cfg)

        row =
          GenTask.Base.screen_row(
            id,
            new_files["prompt.md"],
            new_files["test_harness.exs"],
            blind_grade,
            cfg.model
          )

        append_screen_row(cfg, row)

        case row do
          %{green: true} ->
            backup!(dir, old_files)
            write!(dir, old_files, new_files)
            record(cfg, id, key, "changed", changed_note(old_files, new_files))
            IO.puts("  WRITTEN (blind-verified) — #{changed_note(old_files, new_files)}")
            :changed

          %{green: nil} ->
            record(cfg, id, key, "error", "blind verify environmental: " <> (row[:error] || "?"))
            :error

          %{green: false} ->
            # The grown harness demands more than the prompt carries — a prompt
            # gap, which this tool may not edit. Triage (likely T2.6 material).
            record(
              cfg,
              id,
              key,
              "needs_triage",
              "grown harness not blind-solvable: " <> (row[:first_failure] || "solver failed")
            )

            :needs_triage
        end

      {:error, reason} ->
        record(cfg, id, key, "error", "blind verify call failed: " <> inspect(reason))
        :error
    end
  end

  defp changed_note(old_files, new_files) do
    changed = for {k, v} <- new_files, old_files[k] != v, do: k
    "changed: " <> Enum.join(Enum.sort(changed), ", ")
  end

  defp backup!(dir, old_files) do
    backup_dir = Path.join(@backup_root, Path.basename(dir))
    File.mkdir_p!(backup_dir)
    for {name, body} <- old_files, do: File.write!(Path.join(backup_dir, name), body)
  end

  defp write!(dir, old_files, new_files) do
    for {name, body} <- new_files, old_files[name] != body do
      File.write!(Path.join(dir, name), body)
    end
  end

  defp record(cfg, id, key, outcome, detail) do
    File.mkdir_p!(cfg.logs_dir)

    row = %{
      task: id,
      key: key,
      outcome: outcome,
      detail: String.slice(detail, 0, 500),
      gate_sha: gate_sha(),
      ts: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    File.write!(Path.join(cfg.logs_dir, @ledger), Jason.encode!(row) <> "\n", [:append])
  end

  defp append_screen_row(cfg, row) do
    File.mkdir_p!(cfg.logs_dir)

    File.write!(
      Path.join(cfg.logs_dir, "screen_blind.jsonl"),
      Jason.encode!(row) <> "\n",
      [:append]
    )
  end

  # Load-guard self-test (docs/14 pattern): prove the pure pieces without calls.
  defp self_test do
    files = %{"prompt.md" => "p", "solution.ex" => "s", "test_harness.exs" => "h"}
    key1 = row_key(files)
    key2 = row_key(%{files | "test_harness.exs" => "h2"})

    if key1 == key2, do: raise("row_key must change when content changes")
    if key1 != row_key(files), do: raise("row_key must be deterministic")
    unless matches_only?("016_001_x_01", "016_*"), do: raise("matches_only glob broken")
    if matches_only?("017_001_x_01", "016_*"), do: raise("matches_only over-matches")

    IO.puts("SELF-TEST PASSED (row keying + scoping)")
    System.halt(0)
  end
end

RetroAudit.main(System.argv())
