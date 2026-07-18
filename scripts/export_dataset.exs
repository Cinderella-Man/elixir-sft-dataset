# export_dataset.exs — T3.1: the ONLY sanctioned way to turn this corpus into
# training data. Contract: docs/16-export-contract.md (read it before editing).
#
# Why this exists: 91.7% within-family text overlap BY CONSTRUCTION (a tfim
# child embeds its parent's module AND harness; wt_ embeds the module; bugfix
# embeds the spec + a mutated module). A random split puts near-copies on both
# sides and the resulting val score measures memorisation. So:
#
#   * the split is over FAMILIES (the base idea `a` — 83 of them), never dirs;
#   * it is deterministic (sha256 of the family, no RNG, no seed file);
#   * every row round-trips: re-derived from disk it must reproduce byte-for-byte;
#   * `write_test` golds come from test_harness.exs, NOT solution.ex (its
#     solution.ex is the INPUT module, embedded in the prompt — exporting that
#     as the answer would train "write tests for X" -> X);
#   * repair_ dirs (frozen evidence) are excluded, and the checker proves it.
#
# Usage:
#   mix run scripts/export_dataset.exs                  # write the export
#   mix run scripts/export_dataset.exs -- --check       # GATE: validate on disk
#   mix run scripts/export_dataset.exs -- --selfcheck   # GATE: prove --check bites
#   mix run scripts/export_dataset.exs -- --stats       # census, no writes

alias GenTask.CycleLog

defmodule ExportDataset do
  @moduledoc false

  @out_dir "results/export"
  @split_salt "split-v1:"
  @val_modulus 20

  # The gold file per shape — the single mapping the whole contract rests on.
  @gold_file %{
    single: "solution.ex",
    multifile: "solution.ex",
    fim: "solution.ex",
    test_fim: "solution.ex",
    bugfix: "solution.ex",
    adapt: "solution.ex",
    dedoc: "solution.ex",
    style: "solution.ex",
    dialogue: "solution.ex",
    write_test: "test_harness.exs"
  }

  @weights %{
    single: 1.0,
    multifile: 1.0,
    write_test: 1.0,
    fim: 0.5,
    bugfix: 0.5,
    adapt: 0.5,
    dedoc: 0.5,
    style: 0.5,
    dialogue: 1.0,
    test_fim: 0.25
  }

  # The two contract maps, exposed so tests can assert every Discovery shape
  # is mapped (a new shape missing here must fail the suite, not the export).
  @doc false
  def gold_file_map, do: @gold_file
  @doc false
  def weights_map, do: @weights

  def main(argv) do
    argv = Enum.drop_while(argv, &(&1 == "--"))

    {opts, _, _} =
      OptionParser.parse(argv, strict: [check: :boolean, selfcheck: :boolean, stats: :boolean])

    cond do
      opts[:selfcheck] -> selfcheck()
      opts[:check] -> check()
      opts[:stats] -> stats()
      true -> write_export()
    end
  end

  # ── building examples ───────────────────────────────────────────────────────

  @doc false
  def examples do
    tasks =
      EvalTask.Discovery.all()
      |> Enum.filter(& &1.found)
      |> Enum.reject(&excluded?/1)

    fam_sizes = family_sizes(tasks)
    difficulty = screen_difficulty()

    tasks
    |> Enum.map(&example(&1, fam_sizes, difficulty))
    |> Enum.sort_by(& &1["metadata"]["task"])
  end

  # repair_ dirs are frozen evidence, never training data (docs/16 §2.3).
  defp excluded?(task), do: String.starts_with?(task.name, "repair_")

  # Exported examples per family — emitted so a training run can re-weight by
  # family instead of by shape (docs/16 §4).
  defp family_sizes(tasks), do: Enum.frequencies_by(tasks, &family_of(&1.name))

  defp example(task, fam_sizes, difficulty) do
    prompt = File.read!(Path.join(task.dir, "prompt.md"))
    gold = File.read!(Path.join(task.dir, gold_file!(task.shape)))
    family = family_of(task.name)
    diff = Map.get(difficulty, ab_of(task.name), %{tier: "unscreened", attempts: 0, greens: 0})

    %{
      "messages" => messages(task, prompt, gold),
      "metadata" => %{
        "task" => task.name,
        "shape" => to_string(task.shape),
        "family" => family,
        "split" => split_of(family),
        "sample_weight" => Map.fetch!(@weights, task.shape),
        "family_size" => Map.fetch!(fam_sizes, family),
        "prompt_sha" => CycleLog.content_sha(prompt),
        "completion_sha" => CycleLog.content_sha(gold),
        # T1.4(d): the parent root's blind-screen record as difficulty
        # metadata — derived, advisory, ledger-sourced (docs/16 §4b). Derived
        # shapes inherit their `a_b` root's tier.
        "difficulty_tier" => diff.tier,
        "screen_attempts" => diff.attempts,
        "screen_greens" => diff.greens
      }
    }
  end

  # T1.4 sliver (d): per `a_b` root, the blind-screen ledger aggregated into an
  # advisory difficulty tier — "blind_solvable" (latest verdict green),
  # "keep_class" (latest verdict red: the judged-keep / hard-task family), or
  # "unscreened". Deterministic from logs/screen_blind.jsonl; derived shapes
  # inherit the tier of the root that owns their family task.
  @doc false
  def screen_difficulty(ledger \\ "logs/screen_blind.jsonl") do
    case File.read(ledger) do
      {:ok, body} ->
        body
        |> String.split("\n", trim: true)
        |> Enum.flat_map(fn line ->
          case Jason.decode(line) do
            {:ok, %{"task" => t, "green" => g}} when is_boolean(g) -> [{ab_of(t), g}]
            _ -> []
          end
        end)
        |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
        |> Map.new(fn {ab, greens} ->
          {ab,
           %{
             tier: if(List.last(greens), do: "blind_solvable", else: "keep_class"),
             attempts: length(greens),
             greens: Enum.count(greens, & &1)
           }}
        end)

      _ ->
        %{}
    end
  end

  # The `a_b` group (e.g. "016_001") — one per root; every derived shape maps
  # to its owner root's pair.
  @doc false
  def ab_of(name) do
    case Regex.run(
           ~r/^(?:repair_|bugfix_|tfim_|wt_|adapt_|dedoc_|style_|dialog_)?(\d{3}_\d{3})/,
           name
         ) do
      [_, ab] -> ab
      _ -> raise "cannot derive a_b from #{inspect(name)} — naming convention broken"
    end
  end

  # Single-turn shapes: [user prompt, assistant gold]. The :dialogue shape
  # (docs/16 §5b) replays its dir's frozen chain: spec, each rejected attempt
  # (assistant) with its captured failure report (user), then the accepted
  # gold — deterministic from the dir's files, so round-trip covers it.
  defp messages(%{shape: :dialogue} = task, prompt, gold) do
    turns =
      Path.wildcard(Path.join(task.dir, "attempt_*.code"))
      |> Enum.sort()
      |> Enum.flat_map(fn attempt_file ->
        n = attempt_file |> Path.basename(".code") |> String.trim_leading("attempt_")
        report = File.read!(Path.join(task.dir, "report_#{n}.txt"))

        [
          %{"role" => "assistant", "content" => fence(File.read!(attempt_file))},
          %{"role" => "user", "content" => report}
        ]
      end)

    [%{"role" => "user", "content" => prompt}] ++
      turns ++ [%{"role" => "assistant", "content" => fence(gold)}]
  end

  defp messages(_task, prompt, gold) do
    [
      %{"role" => "user", "content" => prompt},
      %{"role" => "assistant", "content" => fence(gold)}
    ]
  end

  defp gold_file!(shape) do
    case Map.fetch(@gold_file, shape) do
      {:ok, f} -> f
      :error -> raise "unmapped shape #{inspect(shape)} — docs/16 §2.1 must cover every shape"
    end
  end

  defp fence(gold), do: "```elixir\n" <> String.trim_trailing(gold, "\n") <> "\n```"

  # Family = the base idea `a`: the first 3-digit group after any shape prefix.
  # tfim_016_001_07, wt_016_001, bugfix_016_002_01, adapt_016_002 and
  # 016_003_x_01 are ALL family "016" — they share module and prose text
  # (docs/16 §1). An adapt pair embeds BOTH its base's gold and its variation's
  # spec, and both live in the same family `a` — atomicity contains the leak.
  @doc false
  def family_of(name) do
    case Regex.run(~r/^(?:repair_|bugfix_|tfim_|wt_|adapt_|dedoc_|style_|dialog_)?(\d{3})_/, name) do
      [_, a] -> a
      _ -> raise "cannot derive family from #{inspect(name)} — naming convention broken"
    end
  end

  # Deterministic, content-free, family-atomic (docs/16 §3).
  @doc false
  def split_of(family) do
    <<n::32, _::binary>> = :crypto.hash(:sha256, @split_salt <> family)
    if rem(n, @val_modulus) == 0, do: "val", else: "train"
  end

  # ── write ───────────────────────────────────────────────────────────────────

  defp write_export do
    rows = examples()
    File.mkdir_p!(@out_dir)

    {val, train} = Enum.split_with(rows, &(&1["metadata"]["split"] == "val"))

    write_jsonl(Path.join(@out_dir, "train.jsonl"), train)
    write_jsonl(Path.join(@out_dir, "val.jsonl"), val)

    report = report_text(rows, train, val)
    File.write!(Path.join(@out_dir, "report.txt"), report)
    IO.puts(report)

    IO.puts("\nwrote #{@out_dir}/train.jsonl (#{length(train)}), val.jsonl (#{length(val)})")
    IO.puts("Validate with: mix run scripts/export_dataset.exs -- --check")
  end

  defp write_jsonl(path, rows) do
    body = Enum.map_join(rows, "", fn row -> Jason.encode!(row) <> "\n" end)
    File.write!(path, body)
  end

  defp report_text(rows, train, val) do
    by_shape = Enum.frequencies_by(rows, & &1["metadata"]["shape"])
    fams = rows |> Enum.map(& &1["metadata"]["family"]) |> Enum.uniq() |> Enum.sort()
    val_fams = val |> Enum.map(& &1["metadata"]["family"]) |> Enum.uniq() |> Enum.sort()

    """
    === EXPORT (docs/16) ===
    examples: #{length(rows)}   families: #{length(fams)}
    train: #{length(train)}   val: #{length(val)} (#{length(val_fams)} whole families: #{Enum.join(val_fams, ", ")})

    by shape:
    #{Enum.map_join(Enum.sort(by_shape), "\n", fn {s, n} -> "  #{String.pad_trailing(s, 11)} #{n}" end)}
    """
  end

  defp stats do
    rows = examples()
    {val, train} = Enum.split_with(rows, &(&1["metadata"]["split"] == "val"))
    IO.puts(report_text(rows, train, val))
  end

  # ── the gate ────────────────────────────────────────────────────────────────

  defp check do
    case violations(read_export!()) do
      [] ->
        IO.puts("export check: OK ✓ (round-trip, family-atomic split, coverage)")

      vs ->
        IO.puts("export check FAILED — #{length(vs)} violation(s):\n")
        Enum.each(Enum.take(vs, 25), &IO.puts("  " <> &1))
        if length(vs) > 25, do: IO.puts("  … #{length(vs) - 25} more")
        System.halt(1)
    end
  end

  # Every violation class in docs/16 §5. Pure function of the rows -> testable
  # by --selfcheck against planted rows.
  @doc false
  def violations(rows) do
    on_disk =
      EvalTask.Discovery.all()
      |> Enum.filter(& &1.found)
      |> Map.new(&{&1.name, &1})

    exported = MapSet.new(rows, & &1["metadata"]["task"])

    fam_sizes =
      on_disk
      |> Map.values()
      |> Enum.reject(&excluded?/1)
      |> family_sizes()

    split_leaks =
      rows
      |> Enum.group_by(& &1["metadata"]["family"], & &1["metadata"]["split"])
      |> Enum.filter(fn {_f, splits} -> length(Enum.uniq(splits)) > 1 end)
      |> Enum.map(fn {f, _} -> "SPLIT LEAK: family #{f} appears in BOTH train and val" end)

    duplicates =
      rows
      |> Enum.frequencies_by(& &1["metadata"]["task"])
      |> Enum.filter(fn {_n, c} -> c > 1 end)
      |> Enum.map(fn {n, c} -> "DUPLICATE: #{n} appears #{c} times in the export" end)

    row_violations = Enum.flat_map(rows, &row_violations(&1, on_disk, fam_sizes))

    missing =
      on_disk
      |> Map.values()
      |> Enum.reject(&(excluded?(&1) or MapSet.member?(exported, &1.name)))
      |> Enum.map(&"COVERAGE: #{&1.name} exists on disk but was not exported")

    split_leaks ++ duplicates ++ row_violations ++ missing
  end

  defp row_violations(row, on_disk, fam_sizes) do
    meta = row["metadata"]
    name = meta["task"]
    # Dialogues carry 2N+2 messages (docs/16 §5b); every shape starts with the
    # user prompt and ends with the assistant gold.
    msgs = row["messages"]
    user = List.first(msgs)
    assistant = List.last(msgs)

    cond do
      String.starts_with?(name, "repair_") ->
        ["EXCLUDED DATA: #{name} is frozen repair evidence and must not be exported"]

      not Map.has_key?(on_disk, name) ->
        ["UNKNOWN TASK: #{name} is in the export but not on disk"]

      true ->
        task = on_disk[name]
        shape = to_string(task.shape)

        prompt = File.read!(Path.join(task.dir, "prompt.md"))
        gold = File.read!(Path.join(task.dir, gold_file!(task.shape)))

        []
        |> add_if(
          meta["shape"] != shape,
          "SHAPE MISMATCH: #{name} exported as #{meta["shape"]}, disk says #{shape}"
        )
        |> add_if(
          user["content"] != prompt,
          "ROUND-TRIP: #{name} user content != prompt.md on disk"
        )
        |> add_if(
          assistant["content"] != fence(gold),
          "ROUND-TRIP: #{name} assistant content != #{gold_file!(task.shape)} on disk " <>
            "(the #{shape} gold rule, docs/16 §2.1)"
        )
        |> add_if(
          msgs != messages(task, prompt, gold),
          "ROUND-TRIP: #{name} messages differ from re-derivation " <>
            "(multi-turn/frozen-evidence drift, docs/16 §5b)"
        )
        |> add_if(
          meta["family"] != family_of(name),
          "FAMILY: #{name} exported as family #{meta["family"]}"
        )
        |> add_if(
          meta["split"] != split_of(family_of(name)),
          "SPLIT: #{name} exported to #{meta["split"]}, contract says " <>
            "#{split_of(family_of(name))}"
        )
        |> add_if(
          meta["sample_weight"] != Map.fetch!(@weights, task.shape),
          "WEIGHT: #{name} carries sample_weight #{inspect(meta["sample_weight"])}, " <>
            "the #{shape} mapping (docs/16 §4) says #{Map.fetch!(@weights, task.shape)}"
        )
        |> add_if(
          meta["family_size"] != Map.fetch!(fam_sizes, family_of(name)),
          "FAMILY_SIZE: #{name} carries #{inspect(meta["family_size"])}, " <>
            "disk says #{Map.fetch!(fam_sizes, family_of(name))}"
        )
        |> add_if(
          String.trim(user["content"]) == "" or String.trim(assistant["content"]) == "",
          "EMPTY: #{name} has an empty prompt or gold"
        )
    end
  end

  defp add_if(list, true, msg), do: [msg | list]
  defp add_if(list, false, _msg), do: list

  defp read_export! do
    [
      Path.join(@out_dir, "train.jsonl"),
      Path.join(@out_dir, "val.jsonl")
    ]
    |> Enum.flat_map(fn path ->
      case File.read(path) do
        {:ok, body} ->
          body |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)

        {:error, _} ->
          IO.puts("export check: #{path} missing — run the exporter first")
          System.halt(1)
      end
    end)
  end

  # ── selfcheck: prove the gate is not vacuous ────────────────────────────────

  defp selfcheck do
    clean = examples()

    if violations(clean) != [] do
      IO.puts("SELFCHECK FAILED: the clean export does not pass its own gate:")
      Enum.each(Enum.take(violations(clean), 5), &IO.puts("  " <> &1))
      System.halt(1)
    end

    plants = [
      {"straddling family (the leak this whole contract exists to prevent)",
       flip_one_split(clean), ~r/^SPLIT LEAK/},
      {"write_test gold taken from solution.ex (the input module) instead of the harness",
       poison_write_test(clean), ~r/^ROUND-TRIP/},
      {"frozen repair_ evidence exported as training data", plant_repair(clean),
       ~r/^EXCLUDED DATA/},
      {"a dropped example (silent coverage hole)", Enum.drop(clean, 1), ~r/^COVERAGE/},
      {"an emptied gold", empty_gold(clean), ~r/^ROUND-TRIP|^EMPTY/},
      {"a duplicated row", [hd(clean) | clean], ~r/^DUPLICATE/},
      {"a drifted sample_weight", drift_weight(clean), ~r/^WEIGHT/},
      {"a drifted family_size", drift_family_size(clean), ~r/^FAMILY_SIZE/}
    ]

    results =
      Enum.map(plants, fn {label, rows, pattern} ->
        caught = Enum.any?(violations(rows), &Regex.match?(pattern, &1))
        IO.puts("  #{if caught, do: "caught ✓", else: "MISSED ✗"}  #{label}")
        caught
      end)

    if Enum.all?(results) do
      IO.puts(
        "\nexport selfcheck: OK ✓ (clean export passes; all #{length(plants)} planted violations detected)"
      )
    else
      IO.puts("\nSELFCHECK FAILED: the gate did not catch every planted violation")
      System.halt(1)
    end
  end

  defp flip_one_split(rows) do
    # Move ONE row of a train family into val: the family now straddles.
    victim = Enum.find(rows, &(&1["metadata"]["split"] == "train"))
    swapped = put_in(victim, ["metadata", "split"], "val")
    [swapped | Enum.reject(rows, &(&1["metadata"]["task"] == victim["metadata"]["task"]))]
  end

  defp poison_write_test(rows) do
    victim = Enum.find(rows, &(&1["metadata"]["shape"] == "write_test"))
    dir = Path.join("tasks", victim["metadata"]["task"])
    input_module = File.read!(Path.join(dir, "solution.ex"))

    poisoned =
      put_in(victim, ["messages"], [
        Enum.at(victim["messages"], 0),
        %{"role" => "assistant", "content" => fence(input_module)}
      ])

    [poisoned | Enum.reject(rows, &(&1["metadata"]["task"] == victim["metadata"]["task"]))]
  end

  defp plant_repair(rows) do
    repair =
      EvalTask.Discovery.all()
      |> Enum.find(&String.starts_with?(&1.name, "repair_"))

    row = %{
      "messages" => [
        %{"role" => "user", "content" => File.read!(Path.join(repair.dir, "prompt.md"))},
        %{
          "role" => "assistant",
          "content" => fence(File.read!(Path.join(repair.dir, "solution.ex")))
        }
      ],
      "metadata" => %{
        "task" => repair.name,
        "shape" => to_string(repair.shape),
        "family" => family_of(repair.name),
        "split" => split_of(family_of(repair.name)),
        "sample_weight" => 1.0,
        "prompt_sha" => "x",
        "completion_sha" => "x"
      }
    }

    [row | rows]
  end

  defp drift_weight(rows) do
    [put_in(hd(rows), ["metadata", "sample_weight"], 9.9) | tl(rows)]
  end

  defp drift_family_size(rows) do
    [put_in(hd(rows), ["metadata", "family_size"], 0) | tl(rows)]
  end

  defp empty_gold(rows) do
    victim = hd(rows)

    emptied =
      put_in(victim, ["messages"], [
        Enum.at(victim["messages"], 0),
        %{"role" => "assistant", "content" => ""}
      ])

    [emptied | tl(rows)]
  end
end

# test/scripts/* load this file with SCRIPTS_NO_AUTORUN=1 to unit-test the
# module's pure decision functions without executing the CLI.
unless System.get_env("SCRIPTS_NO_AUTORUN"), do: ExportDataset.main(System.argv())
