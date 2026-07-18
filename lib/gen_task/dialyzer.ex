defmodule GenTask.Dialyzer do
  @moduledoc """
  The @spec-truth gate (docs/12 §5.5 rows 15+23; T1.6's calibrated analysis
  promoted from `scripts/dialyzer_golds.exs` into the library so the ACCEPT
  PATH and the retro sweep share one implementation).

  For a staged gold: compile in-process, write beams to a scratch ebin, and
  analyze with `:dialyzer.run/1` against the dialyxir deps PLT. The warning
  set is the T1.6 calibration (2026-07-16, planted regressions of the real
  038/043 defects + a 14-family noise sample): `:overspecs` is ON, and a
  contract-subtype warning is a FINDING only when (a) the function is exported
  AND (b) the success typing's return carries a variant tag the alias-expanded
  spec return lacks. `:warn_opaque` and harness-defined-module unknowns are
  documented false-positive classes and dropped. Sha-keyed waivers
  (`scripts/dialyzer_waivers.jsonl`) turn a human-triaged dialyzer limitation
  into `waived`; any gold edit auto-expires the waiver.

  At accept (`accept_gate/3`, wired into `GenTask.Cycle` after the quality
  gate): `clean`/`waived` pass; `warnings` REJECT with the formatted warning
  text as the repair feedback (a spec lie is repaired like any other failure —
  row 23's requirement that REPAIRED golds are covered falls out of the gate
  suite re-running on every attempt's files); analysis `error`s also reject
  (loud beats silent — `GEN_DIALYZER=0` is the debugging escape). Every
  verdict is ledgered in `logs/dialyzer_golds.jsonl` keyed by
  (gold sha, gate sha, PLT hash) — the rule-7 corollary.
  """

  alias GenTask.{Config, CycleLog}

  @dialyzer_timeout_ms 120_000
  @waivers_file "scripts/dialyzer_waivers.jsonl"
  @ledger "dialyzer_golds.jsonl"

  # ── the accept-path gate ────────────────────────────────────────────────────

  @type gate_result ::
          :ok | {:ok, String.t()} | {:fail, String.t()} | :skip_bundle | :skip_disabled

  @doc """
  Gate a staged gold at accept time. Returns `:ok`/`{:ok, note}` on
  clean-or-waived, `{:fail, detail}` on kept warnings OR analysis errors,
  `:skip_bundle` for `<file>`-bundle golds (v1 scope, same as the retro
  sweep), `:skip_disabled` when `GEN_DIALYZER=0`. Raises when no deps PLT
  exists — a generation run without the PLT must fail loudly, not silently
  skip a quality gate.
  """
  @spec accept_gate(String.t(), %{String.t() => String.t()}, Config.t()) :: gate_result()
  def accept_gate(_id, _files, %Config{dialyzer_gate: false}), do: :skip_disabled

  def accept_gate(id, files, %Config{} = cfg) do
    source = files["solution.ex"]

    cond do
      is_nil(source) ->
        {:fail, "no solution.ex staged"}

      EvalTask.Bundle.bundle?(source) ->
        :skip_bundle

      true ->
        plt =
          default_plt() ||
            raise "no dialyxir deps PLT found — run: mix dialyzer --plt " <>
                    "(GEN_DIALYZER=0 disables the spec-truth gate for debugging only)"

        harness_mods = harness_modules_from_source(files["test_harness.exs"] || "")
        {outcome, detail} = analyze_source(id, source, plt, harness_mods)
        {outcome, detail} = apply_waiver(outcome, detail, id, source)

        append_row(Path.join(cfg.logs_dir, @ledger), %{
          ts: DateTime.utc_now() |> DateTime.to_iso8601(),
          task: id,
          key: row_key(source, gate_sha(plt)),
          gate_sha: gate_sha(plt),
          outcome: outcome,
          detail: String.slice(detail, 0, 4000),
          source: "accept_gate"
        })

        case outcome do
          :clean -> if detail == "", do: :ok, else: {:ok, detail}
          :waived -> {:ok, detail}
          :warnings -> {:fail, detail}
          :error -> {:fail, "dialyzer analysis error (not a spec verdict): " <> detail}
        end
    end
  end

  # ── stage → compile → analyze one gold ──────────────────────────────────────

  @doc "Analyze one gold source. Returns `{:clean | :warnings | :error, detail}`."
  @spec analyze_source(String.t(), String.t(), String.t(), [module()]) ::
          {:clean | :warnings | :error, String.t()}
  def analyze_source(name, source, plt, harness_mods \\ []) do
    stage = Path.join([System.tmp_dir!(), "dialyzer_golds_#{System.pid()}", name])
    ebin = Path.join(stage, "ebin")
    File.rm_rf!(stage)
    File.mkdir_p!(ebin)

    try do
      mods = Code.compile_string(source, "#{name}/solution.ex")
      for {mod, bin} <- mods, do: File.write!(Path.join(ebin, "#{mod}.beam"), bin)

      result = dialyze(ebin, plt, Map.new(mods), harness_mods)

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
  defp dialyze(ebin, plt, mods_map, harness_mods) do
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
          Enum.split_with(warns, fn w ->
            not (private_subtype_noise?(w, mods_map) or known_fp_class?(w, harness_mods))
          end)

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

  # Warning classes proven false-positive on the first full pass (2026-07-16):
  #
  # :warn_opaque — Elixir's opaque structs (MapSet et al.) flowing through
  # higher-order accumulators (Enum.reduce visited-sets) lose opacity in
  # dialyzer's eyes; 9 idiomatic graph/DAG golds false-flagged, zero true
  # positives. Known Elixir<->dialyzer impedance; reach-in style crimes are
  # covered by the S9 lints and semantic review instead.
  #
  # :warn_unknown for HARNESS-DEFINED modules — factory-style golds call
  # modules (MyApp.Repo) that the task's test_harness.exs defines; the staged
  # analysis sees only the gold. Unknowns for any OTHER module are kept —
  # they catch real typos in remote calls.
  defp known_fp_class?({:warn_opaque, _loc, _msg}, _harness_mods), do: true

  defp known_fp_class?({:warn_unknown, _loc, {:unknown_function, {m, _f, _a}}}, harness_mods),
    do: m in harness_mods

  defp known_fp_class?(_warning, _harness_mods), do: false

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
      # Bounded funs (`@spec f(...) :: value when value: term()`) wrap the fun
      # type in :bounded_fun — unhandled, they errored into the conservative
      # keep path and false-flagged 071_003/071_004 on the first v1.1 pass.
      ret =
        case spec do
          {:type, _, :fun, [_args, ret]} -> ret
          {:type, _, :bounded_fun, [{:type, _, :fun, [_args, ret]}, _constraints]} -> ret
        end

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
      # Resolve the fetched definition against its OWNER: Plug.Conn's t() refers
      # to Plug.Conn's own state()/scheme() user types — resolving them against
      # the gold module silently expanded to nothing (bit live: 5 Plug roots
      # false-flagged on the first full pass, 2026-07-16).
      collect_atoms(ast, owner, d - 1, MapSet.put(seen, key), mods_map) ++
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

  # ── harness-module discovery ────────────────────────────────────────────────

  @doc "Modules a harness dir defines (available at eval time, invisible to the staged analysis)."
  @spec harness_modules(String.t()) :: [module()]
  def harness_modules(dir) do
    case File.read(Path.join(dir, "test_harness.exs")) do
      {:ok, body} -> harness_modules_from_source(body)
      _ -> []
    end
  end

  @doc "Same, from harness source already in memory (the accept path stages files, not dirs)."
  @spec harness_modules_from_source(String.t()) :: [module()]
  def harness_modules_from_source(body) do
    for [_, name] <- Regex.scan(~r/^\s*defmodule\s+([\w.]+)/m, body),
        do: Module.concat([name])
  end

  # ── waivers ─────────────────────────────────────────────────────────────────

  # Committed waiver rows (scripts/dialyzer_waivers.jsonl): a human-triaged
  # verdict that a specific (task, solution sha) warning set is a dialyzer
  # limitation, not a spec lie. Sha-keyed, so ANY gold edit auto-expires the
  # waiver (rule-7 corollary). Waived rows count as clean for the exit code but
  # are ledgered as `waived` with the reason attached.
  @doc "Apply a committed sha-keyed waiver to a `:warnings` outcome."
  @spec apply_waiver(atom(), String.t(), String.t(), String.t()) :: {atom(), String.t()}
  def apply_waiver(:warnings, detail, task, source) do
    sol_sha = sha(source)

    waiver =
      case File.read(@waivers_file) do
        {:ok, body} ->
          body
          |> String.split("\n", trim: true)
          |> Enum.map(&Jason.decode!/1)
          |> Enum.find(&(&1["task"] == task and &1["solution_sha"] == sol_sha))

        _ ->
          nil
      end

    case waiver do
      nil -> {:warnings, detail}
      %{"reason" => reason} -> {:waived, "WAIVED: #{reason}\n#{detail}"}
    end
  end

  def apply_waiver(outcome, detail, _task, _source), do: {outcome, detail}

  # ── plumbing shared with the sweep script ───────────────────────────────────

  @doc "First on-disk dialyxir deps PLT, or nil."
  @spec default_plt() :: String.t() | nil
  def default_plt do
    "_build/dev/dialyxir_*_deps-dev.plt" |> Path.wildcard() |> List.first()
  end

  @doc "Rule-7 corollary key: verdicts are owned by (gold content, gate code, PLT)."
  @spec row_key(String.t(), String.t()) :: String.t()
  def row_key(source, gate), do: sha(source) <> ":" <> gate

  @doc """
  The gate sha: this module's code (beam-based, via `CycleLog.gate_sha/1`) +
  the PLT hash. Editing the calibrated filter re-opens every verdict it wrote.
  """
  @spec gate_sha(String.t()) :: String.t()
  def gate_sha(plt) do
    plt_hash =
      case File.read(plt <> ".hash") do
        {:ok, h} -> h
        _ -> sha(File.read!(plt))
      end

    sha(CycleLog.gate_sha([__MODULE__]) <> plt_hash)
  end

  defp sha(data), do: :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)

  @doc "Ledger keys already verdicted (error rows retry, like the retro tools)."
  @spec done_keys(String.t()) :: MapSet.t()
  def done_keys(ledger) do
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

  @doc "Append one ledger row (creates the directory when missing)."
  @spec append_row(String.t(), map()) :: :ok
  def append_row(ledger, row) do
    File.mkdir_p!(Path.dirname(ledger))
    File.write!(ledger, Jason.encode!(row) <> "\n", [:append])
  end
end
