# dialyzer_golds.exs — Dialyzer gate over the gold solutions (T1.6, docs/13 §2.6).
#
# WHY: 019_001 shipped a @spec contradicting its own code; 038_001's build/2
# @spec omitted the `{:error, {:duplicate_ids, _}}` return its code produces;
# 043_001 declared `:ets.tid()` for a named-table atom. Specs are training
# targets (and the hard prerequisite for the dedoc shape, docs/13 §2.3) — they
# must be machine-checked, not trusted.
#
# WHAT: for every single-module `_01` root (bundle roots are counted and
# skipped, like the retro audit's v1 scope; postgres roots are included — this
# gate only compiles, it never opens a DB), compile the gold in-process against
# the project's full dep set, write the beams to a scratch ebin, and analyze
# them with `:dialyzer.run/1` against the dialyxir deps PLT. Per-root staging
# keeps same-named modules (RateLimiter et al.) from colliding in one analysis.
#
# WARNING SET (calibrated on planted regressions of the real 038/043 defects +
# a 14-family noise sample, 2026-07-16): the default set alone MISSES both
# regressions — a spec narrower than the success typing is legal by default.
# Bare `:overspecs` catches them but flagged 12/14 sample roots (private
# helpers with intentionally narrow arg specs; GenServer.call wrappers whose
# success return is any(); t()/alias returns printed collapsed against expanded
# struct types). Final rule: `:overspecs` is ON, and a contract-subtype warning
# is a finding ONLY when (a) the function is exported AND (b) the success
# typing's return carries a VARIANT TAG (tuple/union atom; map keys, struct
# names and booleans/nil excluded) that the alias-EXPANDED spec return lacks —
# the "spec omits a return variant the code produces" class. Aliases are
# expanded from beam typespec chunks (gold modules via their compile-time
# binaries — in-memory modules have no object code). Every other warning class
# is kept for all functions; that is what surfaced the real 015_001 and
# 102_002 pilot findings. Filtered warnings are counted per row (no silent
# caps). DOCUMENTED MISS: a wrong type with the SAME tags (043's original
# tid-vs-atom) is indistinguishable from legitimate narrowing and stays
# invisible — the spot-review layer owns that class.
#
# LEDGER (CONTEXT.md rule 2): every analyzed root gets a JSONL row in
# logs/dialyzer_golds.jsonl keyed by content sha + gate sha (this file + the
# PLT hash) — a relaunch skips finished work; editing this script or rebuilding
# the PLT auto-invalidates old verdicts (rule-7 corollary). `error` rows are
# always retried.
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

defmodule DialyzerGolds do
  @dialyzer_timeout_ms 180_000

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
      opts[:plt] || default_plt() ||
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
          {outcome, detail} = analyze_source(name, source, plt),
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
    gate = gate_sha(plt)
    done = done_keys(ledger)

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
          not File.regular?(sol) -> {todo, done_n, bundle_n}
          EvalTask.Bundle.bundle?(File.read!(sol)) -> {todo, done_n, bundle_n + 1}
          MapSet.member?(done, row_key(File.read!(sol), gate)) -> {todo, done_n + 1, bundle_n}
          true -> {[dir | todo], done_n, bundle_n}
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
      |> Enum.reduce(%{clean: 0, warnings: 0, error: 0}, fn {dir, i}, acc ->
        base = Path.basename(dir)
        source = File.read!(Path.join(dir, "solution.ex"))
        {outcome, detail} = analyze_source(base, source, plt)

        append_row(ledger, %{
          ts: DateTime.utc_now() |> DateTime.to_iso8601(),
          task: base,
          key: row_key(source, gate),
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
      "\ndone: #{counts.clean} clean, #{counts.warnings} with warnings, #{counts.error} errors"
    )

    if counts.warnings > 0,
      do:
        IO.puts("""
        WARNINGS ARE FINDINGS (CONTEXT.md rule 7): each flagged root needs
          Task A — fix the gold's spec/code (defer while a corpus sweep is writing golds;
                   remember the bugfix/wt/tfim cascade + remints on solution edits), AND
          Task B — this gate (weekly CI) already stands; done when the pass reads all-clean.
        Rows: #{ledger} (jq 'select(.outcome=="warnings")').
        """)

    System.halt(if(counts.warnings + counts.error > 0, do: 1, else: 0))
  end

  # ── stage → compile → analyze one gold ──────────────────────────────────────
  defp analyze_source(name, source, plt) do
    stage = Path.join([System.tmp_dir!(), "dialyzer_golds_#{System.pid()}", name])
    ebin = Path.join(stage, "ebin")
    File.rm_rf!(stage)
    File.mkdir_p!(ebin)

    try do
      mods = Code.compile_string(source, "#{name}/solution.ex")
      for {mod, bin} <- mods, do: File.write!(Path.join(ebin, "#{mod}.beam"), bin)

      result = dialyze(ebin, plt, Map.new(mods))

      for {mod, _} <- mods do
        :code.purge(mod)
        :code.delete(mod)
      end

      result
    rescue
      e -> {:error, "compile raised: #{Exception.format(:error, e) |> String.slice(0, 500)}"}
    catch
      kind, reason -> {:error, "compile threw: #{inspect({kind, reason})}"}
    after
      File.rm_rf!(stage)
    end
  end

  # In-process `:dialyzer.run/1` (the CLI boots its own BEAM without Elixir on
  # the path and cannot decode Elixir debug_info — caught by --self-test on the
  # gate's first run). Structured warnings carry {M, F, A}, which is what lets
  # the overspecs filter below be precise instead of text-scraped.
  defp dialyze(ebin, plt, mods_map) do
    task =
      Task.async(fn ->
        :dialyzer.run(
          analysis_type: :succ_typings,
          files_rec: [String.to_charlist(ebin)],
          from: :byte_code,
          init_plt: String.to_charlist(plt),
          check_plt: false,
          warnings: [:overspecs]
        )
      end)

    case Task.yield(task, @dialyzer_timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, warns} ->
        {kept, dropped} =
          Enum.split_with(warns, fn w -> not private_subtype_noise?(w, mods_map) end)

        note =
          if dropped == [],
            do: "",
            else:
              "#{length(dropped)} subtype warning(s) filtered (private helper / any()-return rule)"

        case kept do
          [] ->
            {:clean, note}

          kept ->
            text = kept |> Enum.map(&format_warning/1) |> Enum.join("\n")
            {:warnings, String.trim(note <> "\n" <> text)}
        end

      {:exit, reason} ->
        {:error, "dialyzer exited: #{inspect(reason) |> String.slice(0, 500)}"}

      nil ->
        {:error, "dialyzer timed out after #{div(@dialyzer_timeout_ms, 1000)}s"}
    end
  catch
    :throw, {:dialyzer_error, msg} ->
      {:error, "dialyzer error: #{to_string(msg) |> String.slice(0, 500)}"}
  end

  # Contract-subtype (overspecs-class) warnings are inherently FP-heavy on this
  # corpus: specs narrow args by design (guards can't always prove it), aliases
  # like t()/build_result() print collapsed while the success typing expands, and
  # GenServer.call wrappers have any() success returns. Calibration on planted
  # regressions of the real 038/043 defects (2026-07-16) landed on: a subtype
  # warning is a FINDING only when
  #   1. the function is exported (private helper specs are intentionally
  #      narrower than the over-approximated success typing), AND
  #   2. the success typing's return carries a VARIANT TAG — a tuple/union atom,
  #      not a map key or struct name — that the alias-EXPANDED spec return
  #      lacks (the "spec omits an error variant the code produces" class that
  #      bit in 038_001 and the T2.2 batch).
  # Every non-subtype warning class is kept everywhere (that keeps the real
  # 102_002 invalid_contract and 015_001 no-local-return pilot findings).
  # Accepted, documented miss: a wrong type with the SAME tags (043's original
  # tid-vs-atom) stays invisible — tags equal, refinement indistinguishable
  # from the corpus-wide legitimate narrowing.
  defp private_subtype_noise?(
         {:warn_contract_subtype, _loc, {_kind, [m, f, a, _contract, sig | _]}},
         mods_map
       )
       when is_atom(m) and is_atom(f) and is_integer(a) do
    (Map.has_key?(mods_map, m) and not function_exported?(m, f, a)) or
      not missing_variant_tag?(m, f, a, sig, mods_map)
  end

  defp private_subtype_noise?(_warning, _mods_map), do: false

  # Does the success typing's return mention a variant tag the spec's return
  # (aliases expanded from the beam typespecs) does not cover? On any failure to
  # fetch/expand the spec, err toward KEEPING the warning.
  defp missing_variant_tag?(m, f, a, sig, mods_map) do
    sig_tags = sig_return_tags(sig)

    case spec_return_tags(m, f, a, mods_map) do
      {:ok, spec_tags} -> not MapSet.subset?(sig_tags, spec_tags)
      :error -> true
    end
  end

  # Variant tags in the printed success typing's return part: quoted atoms that
  # are neither map keys (`'k' :=` / `'k' =>`), struct/module names ('Elixir.*'),
  # nor booleans/nil (refinement artifacts, not variants).
  defp sig_return_tags(sig) do
    ret = sig |> to_string() |> String.split("->") |> List.last()

    # Content restricted to atom characters: with `'([^']+)'` the scanner can
    # mispair quotes across atoms (`'__struct__':='Elixir.Trie'` yields a
    # phantom `':='` "atom" once the lookahead rejects the first match — bit
    # live during calibration, 2026-07-16).
    Regex.scan(~r/'([a-zA-Z_][A-Za-z0-9_@.]*)'(?!\s*(?::=|=>))/, ret)
    |> Enum.map(fn [_, atom] -> atom end)
    |> Enum.reject(&(String.starts_with?(&1, "Elixir.") or &1 in ~w(true false nil)))
    |> MapSet.new()
  end

  # Atom literals reachable in the spec's return type, with local AND remote
  # user-type aliases expanded from beam typespec chunks (depth-capped; cycles
  # guarded by a seen-set). Map-field KEYS are skipped — only values/variants
  # count. In-memory modules have no object code, so gold modules are looked up
  # via their compile-time BINARIES (mods_map); remote deps by module atom.
  defp spec_return_tags(m, f, a, mods_map) do
    with {:ok, specs} <- Code.Typespec.fetch_specs(Map.get(mods_map, m, m)),
         [spec | _] <- for({{^f, ^a}, asts} <- specs, ast <- asts, do: ast) do
      {:type, _, :fun, [_args, ret]} = spec
      {:ok, collect_atoms(ret, m, 6, MapSet.new(), mods_map) |> MapSet.new(&to_string/1)}
    else
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp collect_atoms(_ast, _m, 0, _seen, _mods_map), do: []

  defp collect_atoms({:atom, _, a}, _m, _d, _seen, _mods_map),
    do: if(a in [true, false, nil], do: [], else: [a])

  defp collect_atoms(
         {:type, _, :map_field_exact, [{:atom, _, :__struct__}, _v]},
         _m,
         _d,
         _seen,
         _mods_map
       ),
       do: []

  defp collect_atoms({:type, _, field, [_k, v]}, m, d, seen, mods_map)
       when field in [:map_field_exact, :map_field_assoc],
       do: collect_atoms(v, m, d, seen, mods_map)

  defp collect_atoms({:user_type, _, name, args}, m, d, seen, mods_map) do
    expand_alias(m, name, args, m, d, seen, mods_map)
  end

  defp collect_atoms(
         {:remote_type, _, [{:atom, _, rm}, {:atom, _, name}, args]},
         m,
         d,
         seen,
         mods_map
       ) do
    expand_alias(rm, name, args, m, d, seen, mods_map)
  end

  defp collect_atoms({:type, _, _, args}, m, d, seen, mods_map) when is_list(args),
    do: Enum.flat_map(args, &collect_atoms(&1, m, d, seen, mods_map))

  defp collect_atoms({:ann_type, _, [_, t]}, m, d, seen, mods_map),
    do: collect_atoms(t, m, d, seen, mods_map)

  defp collect_atoms(_other, _m, _d, _seen, _mods_map), do: []

  defp expand_alias(owner, name, args, ctx, d, seen, mods_map) do
    key = {owner, name, length(args)}

    with false <- MapSet.member?(seen, key),
         {:ok, types} <- Code.Typespec.fetch_types(Map.get(mods_map, owner, owner)),
         [ast | _] <-
           for({_kind, {^name, ast, vars}} <- types, length(vars) == length(args), do: ast) do
      collect_atoms(ast, ctx, d - 1, MapSet.put(seen, key), mods_map) ++
        Enum.flat_map(args, &collect_atoms(&1, ctx, d - 1, seen, mods_map))
    else
      _ -> Enum.flat_map(args, &collect_atoms(&1, ctx, d - 1, seen, mods_map))
    end
  end

  defp format_warning(w) do
    to_string(:dialyzer.format_warning(w, filename_opt: :basename))
  rescue
    _ -> inspect(w, limit: 20)
  end

  # ── plumbing ────────────────────────────────────────────────────────────────
  defp default_plt do
    "_build/dev/dialyxir_*_deps-dev.plt" |> Path.wildcard() |> List.first()
  end

  # Rule-7 corollary key: verdicts are owned by (gold content, gate code, PLT).
  defp row_key(source, gate), do: sha(source) <> ":" <> gate

  defp gate_sha(plt) do
    plt_hash =
      case File.read(plt <> ".hash") do
        {:ok, h} -> h
        _ -> sha(File.read!(plt))
      end

    sha(File.read!(__ENV__.file) <> plt_hash)
  end

  defp sha(data), do: :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)

  defp done_keys(ledger) do
    case File.read(ledger) do
      {:ok, body} ->
        for line <- String.split(body, "\n", trim: true),
            {:ok, row} <- [Jason.decode(line)],
            row["outcome"] != "error",
            into: MapSet.new(),
            do: row["key"]

      _ ->
        MapSet.new()
    end
  end

  defp append_row(ledger, row) do
    File.mkdir_p!(Path.dirname(ledger))
    File.write!(ledger, Jason.encode!(row) <> "\n", [:append])
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
