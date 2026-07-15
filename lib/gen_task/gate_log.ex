defmodule GenTask.GateLog do
  @moduledoc """
  Gate transparency for the generation loop (Kamil, 2026-07-15 — T1.9).

  One module owns the **ordered manifest of every accept-path gate per shape**, so
  the console can say exactly which check is being applied and what it decided:

      gate [4/8] raise-mutant coverage ... PASS — 6/6 public-function mutants killed

  Rules this encodes:

    * Every gate verdict prints as `gate [k/N] <name> ... PASS|FAIL|SKIPPED (<detail>)`
      where `N` is the total number of gates registered for that shape — a reader can
      see at a glance that gate 6 of 8 never ran.
    * **Dark gates print too.** A gate that exists but is switched off
      (`GEN_SEMANTIC_FLOOR` unset, `GEN_BLIND_RESCREEN=0`) prints `SKIPPED` with the
      flag named, so missing enforcement is visible in every single run instead of
      only in the docs/12 §5.5 parity table.
    * Every verdict is also appended to `logs/gates.jsonl`
      (`{ts, id, shape, gate, idx, total, verdict, detail}`) so a run's gate history
      is greppable after the console is gone (HOW-WE-WORK rule 2).

  The manifests below are the single source of truth for gate numbering. Call sites
  pass `(cfg, id, shape, key, detail)`; an unknown `{shape, key}` raises — a new gate
  must be registered here before it can log, which keeps numbering honest.
  """

  alias GenTask.{Config, CycleLog}

  @type shape :: :base | :variation | :fim | :wtest | :tfim | :bugfix | :adapt
  @type verdict :: :pass | :fail | :skip

  # Ordered gate manifests per shape. Descriptions are printed verbatim — plain
  # language, no invented shorthand.
  @manifests %{
    base: [
      {:autoformat, "canonical formatting (graded bytes are exactly the promoted bytes)"},
      {:green, "compile + green + perfect raw invariants (>=1 passed, 0 failed, 0 errored)"},
      {:quality, "house style + harness standard"},
      {:mutation, "raise-mutant coverage (each public function; whole-module for bundles)"},
      {:stability, "stability re-grade at a derived nonzero ExUnit seed (flake filter)"},
      {:semantic_floor, "semantic-mutant kill floor (GEN_SEMANTIC_FLOOR)"},
      {:promise_audit,
       "promise audit — bite-proven tests for uncovered prompt promises; failing tests " <>
         "machine-prove defects (GEN_PROMISE_AUDIT)"},
      {:blind_rescreen, "accept-time blind re-screen of repaired accepts (GEN_BLIND_RESCREEN)"},
      {:promote_guard, "promotion safety (refuse if the target dir exists; path containment)"}
    ],
    variation: [
      {:distinctness, "public-function set differs from the base and every accepted sibling"},
      {:blind_solve, "independent blind solve — the graded solution never saw the harness"},
      {:autoformat, "canonical formatting (graded bytes are exactly the promoted bytes)"},
      {:green, "compile + green + perfect raw invariants (>=1 passed, 0 failed, 0 errored)"},
      {:quality, "house style + harness standard"},
      {:mutation, "raise-mutant coverage (each public function; whole-module for bundles)"},
      {:stability, "stability re-grade at a derived nonzero ExUnit seed (flake filter)"},
      {:semantic_floor, "semantic-mutant kill floor (GEN_SEMANTIC_FLOOR)"},
      {:promise_audit,
       "promise audit — bite-proven tests for uncovered prompt promises; failing tests " <>
         "machine-prove defects (GEN_PROMISE_AUDIT)"},
      {:blind_rescreen,
       "accept-time blind re-screen of repaired accepts (GEN_BLIND_RESCREEN; " <>
         "variations included — F17-9)"},
      {:promote_guard, "promotion safety (refuse if the target dir exists; path containment)"}
    ],
    fim: [
      {:skeleton,
       "deterministic skeleton integrity (hole matches the parent; candidate locatable)"},
      {:green_nowarn, "reconstructed module green vs the parent harness + zero warnings"},
      {:candidate_mutant, "gutted-candidate mutant must make the parent harness fail"},
      {:promote_guard, "promotion safety (refuse if the target dir exists; path containment)"}
    ],
    wtest: [
      {:parent_gradable, "parent grades on this machine (not a Postgres-tier skip)"},
      {:green_vs_module,
       "gold harness green vs the module (coverage inherited from the parent gate)"},
      {:zero_warnings, "gold harness compiles with zero warnings"},
      {:promote_guard, "promotion safety (refuse if the target dir exists; path containment)"}
    ],
    tfim: [
      {:carvable, "target test block is carvable (top-level, parsable, not covered/rejected)"},
      {:reconstruction, "reconstructed harness (gold block re-inserted) green + zero warnings"},
      {:isolation_kill, "isolated target block kills >=1 raise-mutant of the module"},
      {:promote_guard, "promotion safety (refuse if the target dir exists; path containment)"}
    ],
    bugfix: [
      {:killed_by_tests,
       "seeded semantic mutant is killed by the parent harness (real failing report)"},
      {:reference_green, "gold reference green vs its own staged harness"},
      {:one_line_diff, "buggy module differs from the gold by exactly one line"},
      {:promote_guard, "promotion safety (refuse if the target dir exists; path containment)"}
    ],
    adapt: [
      {:red_gate, "base gold grades RED under the variation harness (adaptation is non-trivial)"},
      {:gold_green, "variation gold green vs the embedded harness copy"},
      {:zero_warnings, "staged pair compiles with zero warnings"},
      {:promote_guard, "promotion safety (refuse if the target dir exists; path containment)"}
    ]
  }

  @doc "The ordered `{key, description}` manifest for `shape` (raises on unknown shape)."
  @spec manifest(shape()) :: [{atom(), String.t()}]
  def manifest(shape), do: Map.fetch!(@manifests, shape)

  @doc "All registered shapes."
  @spec shapes() :: [shape()]
  def shapes, do: Map.keys(@manifests)

  @doc """
  Announce that an expensive gate is starting (mutation sweeps, stability re-grades,
  blind solves — anything that pauses the console for many seconds), so the run
  never looks hung between a task header and the next verdict.
  """
  @spec applying(Config.t(), String.t(), shape(), atom(), String.t()) :: :ok
  def applying(%Config{} = _cfg, _id, shape, key, note) do
    {idx, total, desc} = locate!(shape, key)
    IO.puts("    gate [#{idx}/#{total}] #{desc} — applying#{note_suffix(note)}")
    :ok
  end

  @doc "Log a PASS verdict for gate `key` of `shape` (prints + ledgers)."
  @spec pass(Config.t(), String.t(), shape(), atom(), String.t()) :: :ok
  def pass(cfg, id, shape, key, detail), do: log(cfg, id, shape, key, :pass, detail)

  @doc "Log a FAIL verdict for gate `key` of `shape` (prints + ledgers)."
  @spec fail(Config.t(), String.t(), shape(), atom(), String.t()) :: :ok
  def fail(cfg, id, shape, key, detail), do: log(cfg, id, shape, key, :fail, detail)

  @doc """
  Log a SKIPPED verdict — the gate exists but did not run here (dark flag, not
  applicable to this unit). The detail must say WHY, naming the flag when one exists.
  """
  @spec skip(Config.t(), String.t(), shape(), atom(), String.t()) :: :ok
  def skip(cfg, id, shape, key, detail), do: log(cfg, id, shape, key, :skip, detail)

  @doc """
  Print one sub-check line under a gate (e.g. the house-style gate's individual
  checks): `check [k/N] <label> ... ok|FAIL (<detail>)`. Console only — the parent
  gate's ledger row carries the joined failure detail.
  """
  @spec sub(pos_integer(), pos_integer(), String.t(), :ok | {:fail, String.t()} | :skip) :: :ok
  def sub(idx, total, label, :ok) do
    IO.puts("      check [#{pad(idx, total)}/#{total}] #{label} ... ok")
  end

  def sub(idx, total, label, :skip) do
    IO.puts("      check [#{pad(idx, total)}/#{total}] #{label} ... skipped (no text to check)")
  end

  def sub(idx, total, label, {:fail, detail}) do
    IO.puts("      check [#{pad(idx, total)}/#{total}] #{label} ... FAIL — #{one_line(detail)}")
  end

  @doc "Print a free-form indented detail line under the current gate (console only)."
  @spec detail(String.t()) :: :ok
  def detail(text) do
    IO.puts("      #{one_line(text)}")
  end

  # ---------------------------------------------------------------------------
  # Core
  # ---------------------------------------------------------------------------

  defp log(%Config{} = cfg, id, shape, key, verdict, detail) do
    {idx, total, desc} = locate!(shape, key)
    IO.puts("    gate [#{idx}/#{total}] #{desc} ... #{verdict_text(verdict)}#{suffix(detail)}")

    CycleLog.record_gate(cfg, %{
      id: id,
      shape: shape,
      gate: key,
      idx: idx,
      total: total,
      verdict: verdict,
      detail: detail
    })

    :ok
  end

  defp locate!(shape, key) do
    entries = manifest(shape)
    total = length(entries)

    case Enum.find_index(entries, fn {k, _} -> k == key end) do
      nil ->
        raise ArgumentError,
              "gate #{inspect(key)} is not registered for shape #{inspect(shape)} — " <>
                "add it to the GenTask.GateLog manifest before logging it"

      i ->
        {_, desc} = Enum.at(entries, i)
        {i + 1, total, desc}
    end
  end

  defp verdict_text(:pass), do: "PASS"
  defp verdict_text(:fail), do: "FAIL"
  defp verdict_text(:skip), do: "SKIPPED"

  defp suffix(nil), do: ""
  defp suffix(""), do: ""
  defp suffix(detail), do: " — #{one_line(detail)}"

  defp note_suffix(nil), do: " ..."
  defp note_suffix(""), do: " ..."
  defp note_suffix(note), do: " (#{one_line(note)}) ..."

  # Gate lines must stay one line each — a multi-line detail (a repair report, a
  # survivor list) is flattened; the full text still reaches the per-cycle log and
  # the repair prompt untouched.
  defp one_line(text) do
    flat = text |> String.replace(~r/\s+/, " ") |> String.trim()
    if String.length(flat) > 220, do: String.slice(flat, 0, 217) <> "…", else: flat
  end

  defp pad(i, n), do: String.pad_leading(to_string(i), String.length(to_string(n)))
end
