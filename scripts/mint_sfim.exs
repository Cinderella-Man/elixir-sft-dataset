# Mint DETERMINISTIC code-FIM units (sfim — docs/13 §2.7; roadmap Phase C).
#
#   mix run scripts/mint_sfim.exs [--dry-run] [--limit N] [--only "glob"]
#
# The LLM fim minter selects up to `fim_max_per_task = 3` "interesting" targets
# per root and writes model-authored prose. This miner carves EVERY remaining
# function deterministically: templated prompt (parent spec + skeleton with the
# target blanked), gold = the function's verbatim source span. Units keep the
# existing `_0N` naming and `:fim` shape — the evaluator, exporter, resync gate
# and freshness logic already handle them.
#
# Per-target gates (all local evals, no LLM — a bad carve rejects, never ships):
#   1. carve round-trip: `EvalTask.Fim.build_skeleton(parent, gold)` must locate
#      the gold verbatim (raises otherwise → reject);
#   2. the staged unit grades PERFECT via the real `:fim` evaluator — skeleton
#      reconstruction against the PARENT harness, 1.0 with zero warnings;
#   3. the gutted candidate (every clause body → raise) must make the parent
#      harness FAIL (vacuity guard — an untested function teaches nothing).
# Failures are removed on the spot and sha-ledgered in logs/sfim_rejected.jsonl
# (parent-solution sha + target — a re-run never re-evaluates a dead target).
# Re-runnable: an existing target (any live child carving the same function)
# is skipped via the covered-target scan, same as the LLM minter.

alias GenTask.CycleLog
alias EvalTask.Fim, as: EFim

defmodule MintSfim do
  @moduledoc false

  @reject_ledger "logs/sfim_rejected.jsonl"

  def main(argv) do
    argv = Enum.drop_while(argv, &(&1 == "--"))

    {opts, _, _} =
      OptionParser.parse(argv, strict: [dry_run: :boolean, limit: :integer, only: :string])

    dry? = opts[:dry_run] || false
    dead = dead_keys()

    roots =
      Path.wildcard("tasks/*_01")
      |> Enum.filter(&File.dir?/1)
      |> Enum.filter(fn dir ->
        base = Path.basename(dir)

        match?({_, ""}, Integer.parse(hd(String.split(base, "_")))) and
          (opts[:only] == nil or matches_only?(base, opts[:only]))
      end)
      |> Enum.sort()

    candidates =
      roots
      |> Enum.flat_map(&root_candidates(&1, dead))

    candidates = if opts[:limit], do: Enum.take(candidates, opts[:limit]), else: candidates

    IO.puts(
      "sfim candidates (uncarved targets across #{length(roots)} roots): #{length(candidates)}"
    )

    results =
      if dry? do
        Enum.map(candidates, fn _ -> :would_attempt end)
      else
        Enum.map(candidates, &mint_one/1)
      end

    IO.puts("sfim: #{inspect(Enum.frequencies(results))}")

    if not dry? and Enum.any?(results, &(&1 == :minted)) do
      IO.puts("""
      New _0N fim dirs minted. Validate + commit:
        elixir scripts/validate.exs --fim --only "<globs>"
      """)
    end
  end

  # ── candidate enumeration ───────────────────────────────────────────────────

  defp root_candidates(root_dir, dead) do
    base = Path.basename(root_dir)
    prefix = String.replace_suffix(base, "_01", "")
    sol_path = Path.join(root_dir, "solution.ex")

    with true <- File.regular?(sol_path),
         true <- File.regular?(Path.join(root_dir, "test_harness.exs")),
         src = File.read!(sol_path),
         false <- EvalTask.Bundle.bundle?(src) do
      covered = covered_names(prefix)
      sol_sha = CycleLog.content_sha(src)

      src
      |> target_names()
      |> Enum.reject(fn name -> MapSet.member?(covered, name) end)
      |> Enum.reject(fn name -> MapSet.member?(dead, dead_key(sol_sha, name)) end)
      |> Enum.map(fn name ->
        %{root: root_dir, prefix: prefix, src: src, name: name, sha: sol_sha}
      end)
    else
      _ -> []
    end
  end

  # Function NAMES with at least one def/defp clause (macros skipped). Carving
  # groups ALL clauses/arities of a name, mirroring the fim-child convention.
  defp target_names(src) do
    case Code.string_to_quoted(src) do
      {:ok, ast} ->
        {_ast, acc} =
          Macro.prewalk(ast, [], fn
            {op, _m, [head | _]} = node, acc when op in [:def, :defp] ->
              case fn_name(head) do
                nil -> {node, acc}
                n -> {node, [n | acc]}
              end

            node, acc ->
              {node, acc}
          end)

        acc |> Enum.reverse() |> Enum.uniq()

      _ ->
        []
    end
  end

  defp fn_name({:when, _, [inner | _]}), do: fn_name(inner)
  defp fn_name({name, _, _}) when is_atom(name), do: to_string(name)
  defp fn_name(_), do: nil

  # Names already carved by any live child (`<prefix>_0N`, N >= 2) — scan each
  # child gold's clause heads, all arities count as covered.
  defp covered_names(prefix) do
    Path.wildcard("tasks/#{prefix}_*")
    |> Enum.filter(fn d ->
      File.dir?(d) and
        case d |> Path.basename() |> String.split("_") |> List.last() |> Integer.parse() do
          {n, ""} -> n >= 2
          _ -> false
        end
    end)
    |> Enum.flat_map(fn d ->
      case File.read(Path.join(d, "solution.ex")) do
        {:ok, body} -> target_names(body)
        _ -> []
      end
    end)
    |> MapSet.new()
  end

  # ── minting one target ──────────────────────────────────────────────────────

  defp mint_one(cand) do
    case carve(cand.src, cand.name) do
      {:error, why} ->
        record_dead(cand, "carve: " <> why)
        :uncarvable

      {:ok, gold} ->
        # F24 hard gate: the gold must be a standalone-parseable snippet. The
        # splice-based round-trip/eval gates cannot see truncated attachments
        # (a dangling heredoc closer reconstructs byte-perfectly); this can.
        case Code.string_to_quoted(gold) do
          {:error, {_meta, msg, tok}} ->
            record_dead(
              cand,
              "span not standalone-parseable: #{inspect(msg) |> String.slice(0, 120)} #{inspect(tok)}"
            )

            :uncarvable

          {:ok, _} ->
            mint_parseable(cand, gold)
        end
    end
  end

  defp mint_parseable(cand, gold) do
    case try_skeleton(cand.src, gold) do
      {:error, why} ->
        record_dead(cand, "skeleton: " <> why)
        :uncarvable

      {:ok, skeleton} ->
        stage_and_gate(cand, gold, skeleton)
    end
  end

  defp try_skeleton(src, gold) do
    {:ok, EFim.build_skeleton(src, gold)}
  rescue
    e -> {:error, Exception.message(e) |> String.slice(0, 200)}
  end

  defp stage_and_gate(cand, gold, skeleton) do
    n = next_index(cand.prefix)
    dir = "tasks/#{cand.prefix}_#{String.pad_leading(to_string(n), 2, "0")}"

    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "prompt.md"), prompt_md(cand, skeleton))
    File.write!(Path.join(dir, "solution.ex"), String.trim_trailing(gold, "\n"))

    real = grade(dir, "solution.ex")

    cond do
      not perfect?(real) ->
        File.rm_rf!(dir)
        record_dead(cand, "not perfect via :fim evaluator: #{summary(real)}")
        :rejected

      true ->
        case gut(gold) do
          :error ->
            File.rm_rf!(dir)
            record_dead(cand, "gut failed: no recognizable clause head")
            :gut_failed

          {:ok, gutted_src} ->
            File.write!(Path.join(dir, "gutted.ex"), gutted_src)
            gutted = grade(dir, "gutted.ex")
            File.rm!(Path.join(dir, "gutted.ex"))

            cond do
              gutted["compiled"] != true ->
                # A compile-dead mutant proves nothing (mutation-gate
                # semantics) — the unit is rejected, not blessed.
                File.rm_rf!(dir)
                record_dead(cand, "gutted candidate does not compile — vacuity unprovable")
                :gut_uncompilable

              green?(gutted) ->
                File.rm_rf!(dir)

                record_dead(
                  cand,
                  "vacuous: gutted candidate still green (harness never exercises it)"
                )

                :vacuous

              true ->
                IO.puts("  minted #{Path.basename(dir)} (#{cand.name})")
                :minted
            end
        end
    end
  end

  # Gut the FIRST clause to a raise and drop the rest: the gutted candidate
  # must COMPILE and then FAIL the harness (test-kill, mirroring the mutation
  # gate's semantics — a compile-dead mutant proves nothing). Handles block
  # heads (`… do`), one-liner heads (`, do:`), and multi-line heads whose
  # `do`/`do:` sits on a continuation line. Returns {:ok, gutted} | :error.
  defp gut(gold) do
    lines = String.split(gold, "\n")

    case Enum.find_index(lines, &String.match?(&1, ~r/^\s*defp? /)) do
      nil ->
        :error

      first ->
        indent = Regex.run(~r/^(\s*)/, Enum.at(lines, first)) |> hd()

        do_line =
          Enum.find(first..(length(lines) - 1), fn i ->
            l = Enum.at(lines, i)
            String.match?(l, ~r/\bdo\s*$/) or String.match?(l, ~r/,\s*do:/)
          end)

        case do_line do
          nil ->
            :error

          i ->
            l = Enum.at(lines, i)

            gutted =
              if String.match?(l, ~r/\bdo\s*$/) do
                Enum.take(lines, i + 1) ++
                  [indent <> "  raise \"gutted\"", indent <> "end"]
              else
                Enum.take(lines, i) ++
                  [String.replace(l, ~r/,\s*do:.*$/, ", do: raise \"gutted\"")]
              end

            {:ok, Enum.join(gutted, "\n")}
        end
    end
  end

  # ── the carve: contiguous span of every clause of `name` + attached attrs ──

  @doc false
  def carve(src, name) do
    lines = String.split(src, "\n")
    re = ~r/^  (def|defp) #{Regex.escape(name)}[\s(,]/

    starts = for {l, i} <- Enum.with_index(lines), Regex.match?(re, l), do: i

    case starts do
      [] ->
        {:error, "no clause of #{name} at 2-space indent"}

      _ ->
        spans = Enum.map(starts, fn s -> {attach_attrs(lines, s), clause_end(lines, s)} end)

        case Enum.find_value(spans, fn
               {{:reject, why}, _} -> why
               _ -> nil
             end) do
          why when is_binary(why) ->
            {:error, "attach: " <> why}

          nil ->
            carve_span(lines, spans, re, name)
        end
    end
  end

  defp carve_span(lines, spans, re, name) do
    lo = spans |> Enum.map(fn {{:ok, a}, _} -> a end) |> Enum.min()
    hi = spans |> Enum.map(&elem(&1, 1)) |> Enum.max()

    # Contiguity: nothing but the clauses + attrs + blank lines between lo..hi
    # may belong to OTHER functions. If another def sits inside, reject.
    foreign =
      Enum.any?(lo..hi, fn i ->
        l = Enum.at(lines, i)

        String.match?(l, ~r/^  (def|defp) /) and not Regex.match?(re, l)
      end)

    if foreign do
      {:error, "clauses of #{name} interleave with other functions"}
    else
      {:ok, lines |> Enum.slice(lo..hi) |> Enum.join("\n")}
    end
  end

  # Attach @doc/@spec/@impl/@typedoc + comment lines directly above a clause.
  #
  # Pending/commit design (F24): the span start only advances onto a line
  # PROVEN to belong to an attachable block. A bare heredoc closer directly
  # above the clause means the function is documented — it attaches only by
  # crossing to its `@doc`-family opener, bringing the WHOLE block; if the
  # opener can't be resolved the target is REJECTED, never minted clause-only
  # under visible docs (the prompt's "including the @doc/@spec lines shown
  # above it" contract). Multi-line `@spec` continuations (`)`/`|`/`"`-led
  # lines) cross to their `@spec` opener the same way. The first version
  # committed closers eagerly and halted on doc prose, shipping golds that
  # OPENED with a dangling `"""` (1,084 units, caught by validate --fim's
  # mutant-C verdicts 2026-07-19); the standalone-parse gate in mint_one is
  # the belt to this suspenders.
  defp attach_attrs(lines, start), do: do_attach(lines, start - 1, start)

  defp do_attach(_lines, i, acc) when i < 0, do: {:ok, acc}

  defp do_attach(lines, i, acc) do
    t = String.trim(Enum.at(lines, i))

    cond do
      t in [~s("""), ~s(''')] ->
        case opener_above(lines, i - 1, :doc) do
          {:ok, j} -> do_attach(lines, j - 1, j)
          :not_found -> {:reject, "doc heredoc closer above the clause has no @doc opener"}
        end

      String.starts_with?(t, [")", "|", "\""]) ->
        case opener_above(lines, i - 1, :spec) do
          {:ok, j} -> do_attach(lines, j - 1, j)
          :not_found -> {:reject, "attr continuation line above the clause has no @spec opener"}
        end

      String.starts_with?(t, ["@doc", "@spec", "@impl", "@typedoc", "#"]) ->
        do_attach(lines, i - 1, i)

      true ->
        {:ok, acc}
    end
  end

  # Nearest line above that opens the construct we are inside. :doc wants an
  # `@doc`-family line ending with a heredoc opener; :spec wants an `@spec`
  # line. A bare closer en route is structurally impossible (a heredoc's
  # interior cannot contain its own bare terminator line) and aborts; :spec
  # additionally aborts on blank/def/end lines, which type syntax never spans.
  defp opener_above(_lines, i, _kind) when i < 0, do: :not_found

  defp opener_above(lines, i, kind) do
    t = String.trim(Enum.at(lines, i))

    cond do
      kind == :doc and String.starts_with?(t, "@doc") and
          (String.ends_with?(t, ~s(""")) or String.ends_with?(t, ~s('''))) ->
        {:ok, i}

      kind == :spec and String.starts_with?(t, "@spec") ->
        {:ok, i}

      t in [~s("""), ~s(''')] ->
        :not_found

      kind == :spec and
          (t == "" or t == "end" or String.starts_with?(t, ["def ", "defp ", "defmacro"])) ->
        :not_found

      true ->
        opener_above(lines, i - 1, kind)
    end
  end

  # A clause ends at its matching 2-space `end` (block form), or at the last
  # continuation line of a `, do:` one-liner. The clause's `do` may sit on a
  # CONTINUATION line (multi-line guard heads: `def f(a)\n  when g(a) do`) —
  # the first version checked only the head line, truncated such golds to the
  # bare head, and 120 units died in gut() as "no clause head" (the accidental
  # integrity gate). Search forward for this clause's do-line first; a foreign
  # def encountered en route is left to carve's contiguity check to reject.
  defp clause_end(lines, start) do
    do_i =
      Enum.find(start..(length(lines) - 1), fn i ->
        l = Enum.at(lines, i)
        String.match?(l, ~r/\bdo\s*$/) or String.match?(l, ~r/,\s*do:/)
      end)

    cond do
      do_i == nil ->
        start

      String.match?(Enum.at(lines, do_i), ~r/,\s*do:/) ->
        finish_oneliner(lines, do_i)

      true ->
        Enum.find(do_i..(length(lines) - 1), do_i, fn i -> Enum.at(lines, i) == "  end" end)
    end
  end

  defp finish_oneliner(lines, i) do
    line = Enum.at(lines, i)

    bal =
      (line |> String.graphemes() |> Enum.count(&(&1 in ["(", "[", "{"]))) -
        (line |> String.graphemes() |> Enum.count(&(&1 in [")", "]", "}"])))

    finish_oneliner(lines, i, bal)
  end

  defp finish_oneliner(lines, i, bal) do
    line = Enum.at(lines, i) || ""
    trimmed = String.trim_trailing(line)

    done =
      bal <= 0 and not String.ends_with?(trimmed, [",", "\\", "<>", "++", "|>", "or", "and"]) and
        not (String.trim_leading(Enum.at(lines, i + 1) || "") |> String.starts_with?("|>"))

    if done do
      i
    else
      nxt = Enum.at(lines, i + 1) || ""

      nbal =
        (nxt |> String.graphemes() |> Enum.count(&(&1 in ["(", "[", "{"]))) -
          (nxt |> String.graphemes() |> Enum.count(&(&1 in [")", "]", "}"])))

      finish_oneliner(lines, i + 1, bal + nbal)
    end
  end

  # ── prompt, numbering, grading, ledger ──────────────────────────────────────

  # Single source: GenTask.SfimTemplate — the resync gate re-derives prompts
  # through the same function, so template wording and spec embeds share one
  # drift check.
  defp prompt_md(cand, skeleton) do
    spec = File.read!(Path.join(cand.root, "prompt.md"))
    GenTask.SfimTemplate.prompt(cand.name, spec, skeleton)
  end

  defp next_index(prefix) do
    Path.wildcard("tasks/#{prefix}_*")
    |> Enum.map(fn d ->
      case d |> Path.basename() |> String.split("_") |> List.last() |> Integer.parse() do
        {n, ""} -> n
        _ -> 1
      end
    end)
    |> Enum.max(fn -> 1 end)
    |> Kernel.+(1)
  end

  defp grade(dir, sol) do
    eval = Path.join(File.cwd!(), "scripts/eval_task.exs")
    timeout_s = System.get_env("EVAL_TIMEOUT_S", "240")

    {out, _} =
      System.cmd("timeout", ["--signal=KILL", timeout_s, "elixir", eval, dir, sol],
        stderr_to_stdout: true
      )

    line =
      out
      |> String.split("\n", trim: true)
      |> Enum.reverse()
      |> Enum.find("{}", &String.starts_with?(&1, "{"))

    case Jason.decode(line) do
      {:ok, json} -> json
      {:error, _} -> %{}
    end
  end

  defp green?(json) do
    json["compiled"] == true and (json["tests_passed"] || 0) > 0 and
      (json["tests_failed"] || 0) == 0 and (json["tests_errors"] || 0) == 0
  end

  defp perfect?(json), do: green?(json) and get_in(json, ["score", "overall"]) == 1.0

  defp summary(json),
    do:
      "compiled=#{json["compiled"]} passed=#{json["tests_passed"]}/#{json["tests_total"]} " <>
        "overall=#{get_in(json, ["score", "overall"])}"

  defp dead_key(sol_sha, name), do: sol_sha <> ":" <> name

  defp dead_keys do
    case File.read(@reject_ledger) do
      {:ok, body} ->
        for line <- String.split(body, "\n", trim: true),
            {:ok, row} <- [Jason.decode(line)],
            into: MapSet.new(),
            do: row["key"]

      _ ->
        MapSet.new()
    end
  end

  defp record_dead(cand, why) do
    File.mkdir_p!(Path.dirname(@reject_ledger))

    File.write!(
      @reject_ledger,
      Jason.encode!(%{
        key: dead_key(cand.sha, cand.name),
        root: Path.basename(cand.root),
        target: cand.name,
        why: String.slice(why, 0, 500),
        ts: DateTime.utc_now() |> DateTime.to_iso8601()
      }) <> "\n",
      [:append]
    )
  end

  defp matches_only?(name, patterns) do
    patterns
    |> String.split(",", trim: true)
    |> Enum.any?(fn glob ->
      Regex.match?(~r/\A#{glob |> Regex.escape() |> String.replace("\\*", ".*")}\z/, name)
    end)
  end
end

MintSfim.main(System.argv())
