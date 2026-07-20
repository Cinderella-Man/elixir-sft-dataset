# lint_harnesses.exs — deterministic harness anti-pattern lint (docs/10 R5a) and the
# prompt-side hidden-contract backfill (R5b).
#
# Scans every dir carrying BOTH a prompt.md and a test_harness.exs (the `_01` tasks
# and their `wt_` derivatives) for the §1.1 anti-pattern families:
#
#   * `interval-opt: :infinity` in the harness while prompt.md never mentions
#     `:infinity` — the hidden "disable the timer" contract (50 harnesses at audit).
#   * `send(server, :cleanup | :sweep | :tick)` while prompt.md never documents the
#     message — the hidden manual-trigger contract (36 at audit).
#   * `:sys.get_state` / `:sys.replace_state` — internal-state overfitting (62).
#     REPORT-ONLY: fixing these means rewriting tests to assert observable behavior,
#     which cascades into tfim gold blocks — LLM/human surgery, not scriptable.
#   * `assert inspect(` and `assert_raise Mod, "exact message"` — brittle asserts.
#     Report-only.
#
# `--fix-prompts` appends an "## Additional interface contract" section to the
# affected `_01` prompt.md (and inserts it into the matching `wt_` prompt.md before
# its "## Module under test" section) stating the `:infinity` and manual-trigger
# contracts. The wording is truthful by construction: the reference harness is green
# while exercising exactly these behaviors. Idempotent (skips prompts already
# carrying the section). FIM/tfim children embed the parent MODULE/harness, never
# the parent prompt, so no further cascade exists.
#
# Usage:
#   mix run scripts/lint_harnesses.exs                 # report only
#   mix run scripts/lint_harnesses.exs --fix-prompts   # apply the R5b backfill
#   mix run scripts/lint_harnesses.exs --only "001_*"  # restrict either mode

defmodule LintHarnesses do
  @moduledoc false

  @trigger_atoms ~w(cleanup sweep tick)
  @section_header "## Additional interface contract"

  def main(argv) do
    {opts, _, _} =
      OptionParser.parse(argv, strict: [fix_prompts: :boolean, only: :string])

    findings =
      for dir <- Path.wildcard("tasks/*"),
          File.dir?(dir),
          match_only?(Path.basename(dir), opts[:only]),
          harness_path = Path.join(dir, "test_harness.exs"),
          prompt_path = Path.join(dir, "prompt.md"),
          File.regular?(harness_path) and File.regular?(prompt_path),
          finding = lint(dir, File.read!(harness_path), File.read!(prompt_path)),
          finding != nil do
        finding
      end

    report(findings)

    if opts[:fix_prompts] do
      fix_prompts(findings)
    else
      IO.puts("\n(report only — `--fix-prompts` applies the :infinity/manual-trigger backfill)")
    end
  end

  # ── detection ───────────────────────────────────────────────────────────────

  # Frozen-evidence shapes (docs/13 §1.5): repair_/dialog_/style_ dirs carry a
  # snapshot of their root's harness at mint time and are never strengthened in
  # place — coverage-gap findings on them are permanent noise; their quality
  # rides on the root the cascade fixes.
  defp frozen_evidence?(dir) do
    String.starts_with?(Path.basename(dir), ["repair_", "dialog_", "style_"])
  end

  defp lint(dir, harness, prompt) do
    finding = %{
      dir: dir,
      infinity_keys: undocumented_infinity_keys(harness, prompt),
      trigger_atoms: undocumented_trigger_atoms(harness, prompt),
      dormant_timer_keys:
        if(frozen_evidence?(dir), do: [], else: dormant_timer_keys(harness, prompt)),
      unconfigured_timer_keys:
        if(frozen_evidence?(dir), do: [], else: unconfigured_timer_keys(harness, prompt)),
      sys_get_state: count(harness, ~r/:sys\.(get_state|replace_state)/),
      inspect_asserts: count(harness, ~r/assert\s+inspect\(/),
      exact_raise_msgs: count(harness, ~r/assert_raise\s+[\w.]+,\s*"/)
    }

    if finding.infinity_keys == [] and finding.trigger_atoms == [] and
         finding.dormant_timer_keys == [] and finding.unconfigured_timer_keys == [] and
         finding.sys_get_state == 0 and finding.inspect_asserts == 0 and
         finding.exact_raise_msgs == 0,
       do: nil,
       else: finding
  end

  # Interval-style option keys passed as :infinity that the prompt never mentions.
  # Key shape is deliberately narrow (interval/period/_ms) so a legitimate
  # `timeout: :infinity` GenServer option or a `max_uses: :infinity` capacity —
  # different semantics — is not misflagged.
  defp undocumented_infinity_keys(harness, prompt) do
    if String.contains?(prompt, ":infinity") do
      []
    else
      ~r/(\w*(?:interval|period)\w*|\w+_ms):\s*:infinity/
      |> Regex.scan(harness, capture: :all_but_first)
      |> List.flatten()
      |> Enum.uniq()
    end
  end

  # Periodic-action trigger messages sent straight to the server under test while
  # the prompt never documents the message. The word boundary matters: a bare
  # `String.contains?(prompt, ":cleanup")` false-matches inside the OPTION name
  # `:cleanup_interval_ms` — an option being documented does not document the
  # message (`\b` fails before `_`, so the regex distinguishes them).
  defp undocumented_trigger_atoms(harness, prompt) do
    ~r/send\(\s*\w+,\s*:(#{Enum.join(@trigger_atoms, "|")})\s*\)/
    |> Regex.scan(harness, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.reject(&Regex.match?(~r/:#{&1}\b/, prompt))
  end

  # The prompt promises an AUTOMATIC periodic timer (`Process.send_after` plus a
  # configurable :interval/:period option) but no test ever ENABLES it — a
  # solution whose scheduling helper is a no-op passes such a suite while
  # violating the prompt's explicit contract (the 001_001 semantic-review
  # finding class, 2026-07-20). Documenting `:infinity` (the R5b backfill) does
  # NOT clear this: the escape hatch being documented is no excuse for every
  # test taking it. Two confidence tiers:
  #
  #   * CONFIRMED (`dormant_timer_keys`) — the harness explicitly passes the
  #     key as `:infinity` and never with any other value. Every entry is
  #     actionable coverage debt (close_gaps; never a prompt edit).
  #   * NEEDS-READ (`unconfigured_timer_keys`) — the key never appears in the
  #     harness in keyword position at all. Mixed: relying on an hour-scale
  #     default IS the same gap, but a harness passing the interval as a
  #     POSITIONAL argument (the 015 heartbeat family observes real timer
  #     firings via `assert_receive`) is invisible to this text lint —
  #     hand-triage, do not batch-fix.
  #
  # Key shape is interval/period-only — `window_ms`-style per-call arguments
  # are not timer options and must not flag.
  defp promised_timer_keys(prompt) do
    if String.contains?(prompt, "Process.send_after") do
      ~r/:(\w*(?:interval|period)\w*)\b/
      |> Regex.scan(prompt, capture: :all_but_first)
      |> List.flatten()
      |> Enum.uniq()
      # An atom the prompt uses as an ERROR REASON (`{:error, :invalid_interval}`)
      # is not a timer option, however interval-shaped its name.
      |> Enum.reject(fn key -> String.contains?(prompt, "{:error, :#{key}") end)
    else
      []
    end
  end

  defp dormant_timer_keys(harness, prompt) do
    promised_timer_keys(prompt)
    |> Enum.filter(fn key -> Regex.match?(~r/#{key}:\s*:infinity/, harness) end)
    |> Enum.reject(fn key -> Regex.match?(~r/#{key}:\s*(?!:infinity)\S/, harness) end)
  end

  defp unconfigured_timer_keys(harness, prompt) do
    promised_timer_keys(prompt)
    |> Enum.reject(fn key -> Regex.match?(~r/#{key}:/, harness) end)
  end

  defp count(harness, re), do: length(Regex.scan(re, harness))

  # ── report ──────────────────────────────────────────────────────────────────

  defp report(findings) do
    fixable = Enum.filter(findings, &(&1.infinity_keys != [] or &1.trigger_atoms != []))
    dormant = Enum.filter(findings, &(&1.dormant_timer_keys != []))
    unconfigured = Enum.filter(findings, &(&1.unconfigured_timer_keys != []))
    sys = Enum.filter(findings, &(&1.sys_get_state > 0))
    brittle = Enum.filter(findings, &(&1.inspect_asserts + &1.exact_raise_msgs > 0))

    IO.puts("""
    == Harness lint (#{length(findings)} dir(s) with findings) ==

    hidden contracts fixable prompt-side (--fix-prompts): #{length(fixable)}
    promised timer disabled by every test (CONFIRMED, report-only): #{length(dormant)}
    promised timer never configured (NEEDS-READ, report-only): #{length(unconfigured)}
    :sys.get_state internal-state asserts (report-only): #{length(sys)}
    brittle asserts (inspect/exact raise msg, report-only): #{length(brittle)}
    """)

    for f <- fixable do
      IO.puts(
        "  FIXABLE #{f.dir}  infinity=#{inspect(f.infinity_keys)} triggers=#{inspect(f.trigger_atoms)}"
      )
    end

    for f <- dormant do
      IO.puts("  DORMANT #{f.dir}  timer_keys=#{inspect(f.dormant_timer_keys)}")
    end

    for f <- unconfigured do
      IO.puts("  DORMANT? #{f.dir}  timer_keys=#{inspect(f.unconfigured_timer_keys)}")
    end

    for f <- sys, do: IO.puts("  SYS     #{f.dir}  :sys.* calls=#{f.sys_get_state}")

    for f <- brittle do
      IO.puts(
        "  BRITTLE #{f.dir}  inspect=#{f.inspect_asserts} exact_raise=#{f.exact_raise_msgs}"
      )
    end
  end

  # ── the R5b prompt-side backfill ────────────────────────────────────────────

  # Only `_01` dirs get the section appended directly; the matching `wt_` prompt
  # embeds the same spec and gets it inserted before its "## Module under test".
  # (`wt_` findings themselves resolve via their parent — the harness is a byte copy.)
  defp fix_prompts(findings) do
    # dedoc_ prompts are DELIBERATELY de-documented — backfilling contract
    # sections into them would undo the shape's whole point, so they are
    # report-only here even when the detector fires (their harness is the
    # root's; the root carries any real fix).
    fixable =
      findings
      |> Enum.filter(&(&1.infinity_keys != [] or &1.trigger_atoms != []))
      |> Enum.reject(&String.starts_with?(Path.basename(&1.dir), ["wt_", "dedoc_"]))

    IO.puts("\nApplying prompt-side backfill to #{length(fixable)} _01 prompt(s) ...")

    Enum.each(fixable, fn f ->
      section = section_for(f)
      patch_parent(f.dir, section)
      patch_wt(f.dir, section)
    end)

    IO.puts("Done. Re-run without --fix-prompts to confirm the report is clean.")
  end

  defp section_for(f) do
    infinity_bullets =
      for key <- f.infinity_keys do
        "- The `:#{key}` option may also be `:infinity`, in which case the periodic\n" <>
          "  timer is never scheduled — nothing runs automatically."
      end

    trigger_bullets =
      for atom <- f.trigger_atoms do
        "- Sending the server process a bare `:#{atom}` message performs one #{atom}\n" <>
          "  pass immediately — the same work the periodic timer performs."
      end

    Enum.join([@section_header | infinity_bullets ++ trigger_bullets], "\n\n")
  end

  # The parent's section lives at the end of prompt.md; the wt_ copy sits directly
  # before "## Module under test". Both patchers are idempotent per BULLET (not just
  # per section), so a later lint improvement that surfaces a new bullet extends the
  # existing section instead of being skipped.
  defp patch_parent(dir, section) do
    path = Path.join(dir, "prompt.md")
    body = File.read!(path)

    case missing_content(body, section) do
      nil ->
        IO.puts("  = #{path} (up to date)")

      addition ->
        File.write!(path, String.trim_trailing(body) <> "\n\n" <> addition <> "\n")
        IO.puts("  + #{path}")
    end
  end

  defp patch_wt(dir, section) do
    base = Path.basename(dir)
    wt_path = Path.join(["tasks", "wt_" <> String.replace_suffix(base, "_01", ""), "prompt.md"])

    with true <- File.regular?(wt_path),
         body = File.read!(wt_path),
         addition when addition != nil <- missing_content(body, section),
         [before, rest] <- String.split(body, "\n## Module under test", parts: 2) do
      File.write!(
        wt_path,
        String.trim_trailing(before) <>
          "\n\n" <> addition <> "\n\n## Module under test" <> rest
      )

      IO.puts("  + #{wt_path}")
    else
      false -> IO.puts("  ! #{wt_path} missing — skipped")
      nil -> IO.puts("  = #{wt_path} (up to date)")
      _ -> IO.puts("  ! #{wt_path} has no '## Module under test' anchor — skipped")
    end
  end

  # What of `section` is not yet in `body`: the whole section, just the missing
  # bullets (when the header is already present), or nil when up to date.
  defp missing_content(body, section) do
    [header | bullets] = String.split(section, "\n\n")
    missing = Enum.reject(bullets, &String.contains?(body, &1))

    cond do
      not String.contains?(body, header) -> section
      missing == [] -> nil
      true -> Enum.join(missing, "\n\n")
    end
  end

  defp match_only?(_name, nil), do: true

  defp match_only?(name, patterns) do
    patterns
    |> String.split(",", trim: true)
    |> Enum.any?(fn glob ->
      Regex.match?(~r/\A#{glob |> Regex.escape() |> String.replace("\\*", ".*")}\z/, name)
    end)
  end
end

LintHarnesses.main(System.argv())
