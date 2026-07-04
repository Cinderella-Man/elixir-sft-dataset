defmodule GenTask.Catalog do
  @moduledoc """
  Parse `tasks/tasks.md` into base ideas, and enumerate the two work-lists that
  drive a generation run (see `docs/04-task-generation-loop.md` §5, §9):

    1. **todo base ideas** — base ideas with no `tasks/NNN_001_*_01` directory yet;
    2. **backfill seeds** — existing accepted `_01` directories (base or variation)
       that still lack variations and/or FIM derivatives.

  It also owns the *idempotent, insert-only* `tasks.md` mutation used when an
  accepted variation is promoted.

  ## Grammar (file order is significant)

    * base idea      — `^### (\\d+)\\. (.+)$`
    * variation      — `^### Task (\\d+) - (V\\d+) - (.+)$`
    * anything else `###`/`##` — a **section header**: not an idea; it terminates the
      current idea's description and starts nothing.
  """

  alias GenTask.Config

  @base_re ~r/^###\s+(\d+)\.\s+(.+?)\s*$/
  @variation_re ~r/^###\s+Task\s+(\d+)\s+-\s+(V\d+)\s+-\s+(.+?)\s*$/
  @header_re ~r/^##/

  defmodule Idea do
    @moduledoc "A single base idea parsed from `tasks.md`."
    @type t :: %__MODULE__{
            num: pos_integer(),
            name: String.t(),
            desc: String.t(),
            slug: String.t(),
            task_id: String.t(),
            done?: boolean()
          }
    defstruct [:num, :name, :desc, :slug, :task_id, done?: false]
  end

  defmodule Seed do
    @moduledoc """
    An existing accepted `_01` directory considered for backfill, plus which
    derivatives it still needs.
    """
    @type t :: %__MODULE__{
            dir: String.t(),
            task_id: String.t(),
            num: pos_integer(),
            b: pos_integer(),
            base?: boolean(),
            skip?: boolean(),
            needs_variations?: boolean(),
            needs_fim?: boolean(),
            needs_write_test?: boolean(),
            needs_test_fim?: boolean()
          }
    defstruct [
      :dir,
      :task_id,
      :num,
      :b,
      :base?,
      skip?: false,
      needs_variations?: false,
      needs_fim?: false,
      needs_write_test?: false,
      needs_test_fim?: false
    ]
  end

  # ---------------------------------------------------------------------------
  # Parsing
  # ---------------------------------------------------------------------------

  @doc """
  Parse the catalog file at `cfg.tasks_md` into `%Idea{}` structs (file order),
  computing `done?` against `cfg.tasks_dir`.
  """
  @spec ideas(Config.t()) :: [Idea.t()]
  def ideas(%Config{} = cfg) do
    cfg.tasks_md
    |> File.read!()
    |> parse_string(cfg.tasks_dir)
  end

  @doc """
  Parse catalog `content` into `%Idea{}` structs. `tasks_dir` is used only to
  compute `done?` (existence of a matching `_01` directory).
  """
  @spec parse_string(String.t(), String.t()) :: [Idea.t()]
  def parse_string(content, tasks_dir \\ "tasks") do
    content
    |> String.split("\n")
    |> collect(nil, [])
    |> Enum.reverse()
    |> Enum.map(fn {num, name, desc_lines} ->
      slug = slug(name)

      %Idea{
        num: num,
        name: name,
        desc: desc_lines |> Enum.reverse() |> Enum.join("\n") |> String.trim(),
        slug: slug,
        task_id: task_id(num, slug),
        done?: done?(num, tasks_dir)
      }
    end)
  end

  # Fold over lines; `cur` = {num, name, desc_lines} | nil.
  defp collect([], nil, acc), do: acc
  defp collect([], cur, acc), do: [cur | acc]

  defp collect([line | rest], cur, acc) do
    cond do
      match = Regex.run(@base_re, line) ->
        [_, num, name] = match
        acc = if cur, do: [cur | acc], else: acc
        collect(rest, {String.to_integer(num), String.trim(name), []}, acc)

      # A variation line or any other ##/### header terminates the current idea.
      Regex.match?(@variation_re, line) or Regex.match?(@header_re, line) ->
        acc = if cur, do: [cur | acc], else: acc
        collect(rest, nil, acc)

      cur == nil ->
        collect(rest, nil, acc)

      true ->
        {num, name, desc} = cur
        collect(rest, {num, name, [line | desc]}, acc)
    end
  end

  # ---------------------------------------------------------------------------
  # Identity helpers
  # ---------------------------------------------------------------------------

  @doc "Cosmetic slug: downcase, non-alphanumeric runs → `_`, trim underscores."
  @spec slug(String.t()) :: String.t()
  def slug(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
  end

  @doc "Zero-padded 3-digit string for a task number."
  @spec pad3(integer()) :: String.t()
  def pad3(num), do: String.pad_leading(to_string(num), 3, "0")

  @doc "The canonical base `_01` task id for an idea number + slug."
  @spec task_id(integer(), String.t()) :: String.t()
  def task_id(num, slug), do: "#{pad3(num)}_001_#{slug}_01"

  @doc "True if any `tasks_dir/NNN_001_*_01` directory already exists for `num`."
  @spec done?(integer(), String.t()) :: boolean()
  def done?(num, tasks_dir \\ "tasks") do
    "#{tasks_dir}/#{pad3(num)}_001_*_01"
    |> Path.wildcard()
    |> Enum.any?(&File.dir?/1)
  end

  # ---------------------------------------------------------------------------
  # Work-list 1: todo base ideas
  # ---------------------------------------------------------------------------

  @doc """
  The ordered list of base ideas to generate this run: not yet done, restricted
  by `:only_idea` / `:from` / `:to` and finally truncated to `:limit`.
  """
  @spec todo_bases([Idea.t()], Config.t()) :: [Idea.t()]
  def todo_bases(ideas, %Config{} = cfg) do
    ideas
    |> Enum.reject(& &1.done?)
    |> Enum.filter(&in_scope?(&1.num, cfg))
    |> maybe_limit(cfg.limit)
  end

  defp in_scope?(num, %Config{only_idea: only}) when is_integer(only), do: num == only

  defp in_scope?(num, %Config{from: from, to: to}) do
    (is_nil(from) or num >= from) and (is_nil(to) or num <= to)
  end

  defp maybe_limit(list, nil), do: list
  defp maybe_limit(list, n) when is_integer(n), do: Enum.take(list, n)

  # ---------------------------------------------------------------------------
  # Work-list 2: backfill seeds
  # ---------------------------------------------------------------------------

  @doc """
  Existing accepted `_01` directories that still need derivatives.

  A base `_01` (b == 1) needs variations when no `_002_*_01` sibling exists. Any
  `_01` (base or variation) needs FIM when it has no `_02+` subtask sibling.
  Returned in directory-name order, restricted by the same idea-number scope.
  """
  @spec backfill_seeds(Config.t()) :: [Seed.t()]
  def backfill_seeds(%Config{} = cfg) do
    cfg
    |> all_seeds()
    |> Enum.filter(&(GenTask.Work.pending(&1, cfg) != %{}))
    |> Enum.filter(&in_scope?(&1.num, cfg))
    # GEN_LIMIT bounds each work-list: at most N base ideas AND at most N backfill
    # seeds per run (docs/05 #7 — it used to bound only new bases).
    |> maybe_limit(cfg.limit)
  end

  @doc "Every accepted `_01` seed on disk (whether or not it needs work) — for status."
  @spec all_seeds(Config.t()) :: [Seed.t()]
  def all_seeds(%Config{} = cfg) do
    "#{cfg.tasks_dir}/*_01"
    |> Path.wildcard()
    |> Enum.filter(&File.dir?/1)
    |> Enum.sort()
    |> Enum.map(&seed(&1, cfg))
    |> Enum.reject(&is_nil/1)
  end

  defp seed(dir, %Config{} = cfg) do
    base = Path.basename(dir)
    parts = String.split(base, "_")

    with [a, b | _] <- parts,
         {num, ""} <- Integer.parse(a),
         {bnum, ""} <- Integer.parse(b),
         "01" <- List.last(parts) do
      base? = bnum == 1

      # Which work each seed still needs is defined ONCE, in the `GenTask.Work`
      # registry (top-up semantics, gradable-skip exclusions — see its moduledoc);
      # the flags here are a convenience projection of `Work.missing/3`.
      bare = %Seed{
        dir: dir,
        task_id: base,
        num: num,
        b: bnum,
        base?: base?,
        skip?: gradable_skip?(dir)
      }

      %Seed{
        bare
        | needs_variations?: GenTask.Work.missing(:variations, bare, cfg) > 0,
          needs_fim?: GenTask.Work.missing(:fim, bare, cfg) > 0,
          needs_write_test?: GenTask.Work.missing(:write_test, bare, cfg) > 0,
          needs_test_fim?: GenTask.Work.missing(:test_fim, bare, cfg) > 0
      }
    else
      _ -> nil
    end
  end

  @doc "Number of variation `_01` dirs (V1..V3 → `_002`.._004`) present for idea `a`."
  @spec count_variations(String.t(), String.t()) :: non_neg_integer()
  def count_variations(tasks_dir, a) do
    Enum.count(2..4, fn b ->
      "#{tasks_dir}/#{a}_#{pad3(b)}_*_01"
      |> Path.wildcard()
      |> Enum.any?(&File.dir?/1)
    end)
  end

  @doc "Number of FIM subtask dirs (`_02+`) present under the `a_b_*_01` task."
  @spec count_fim(String.t(), String.t(), String.t()) :: non_neg_integer()
  def count_fim(tasks_dir, a, b) do
    "#{tasks_dir}/#{a}_#{b}_*"
    |> Path.wildcard()
    |> Enum.count(fn d -> File.dir?(d) and fim_subtask?(Path.basename(d)) end)
  end

  # A FIM subtask directory ends in a subtask index >= 2 (e.g. `_02`, `_10`).
  defp fim_subtask?(basename) do
    case Integer.parse(List.last(String.split(basename, "_"))) do
      {n, ""} -> n >= 2
      _ -> false
    end
  end

  @doc "Number of test-FIM subtask dirs (`tfim_<a>_<b>_*`) present for the `a_b_*_01` task."
  @spec count_tfim(String.t(), String.t(), String.t()) :: non_neg_integer()
  def count_tfim(tasks_dir, a, b) do
    "#{tasks_dir}/tfim_#{a}_#{b}_*"
    |> Path.wildcard()
    |> Enum.count(&File.dir?/1)
  end

  # A `_01` whose evaluator run is `skipped` — Postgres-tier (`manifest.exs` carries
  # `db: :postgres`) with no host to grade against — can never mint a green wtest or a
  # gated tfim (both stage the parent, which grades `skipped`, not green). Excluding it
  # keeps such a seed out of the wtest/tfim backfill; otherwise it is re-attempted every
  # run and its derivatives land in `logs/errors/` forever (docs/06 §6 `gradable_skip?`).
  @spec gradable_skip?(String.t()) :: boolean()
  defp gradable_skip?(dir) do
    manifest = Path.join(dir, "manifest.exs")
    File.regular?(manifest) and File.read!(manifest) =~ ~r/db:\s*:postgres/
  end

  # ---------------------------------------------------------------------------
  # Idempotent tasks.md insertion for an accepted variation
  # ---------------------------------------------------------------------------

  @doc """
  Insert a `### Task N - Vn - Name` entry (plus its description) into catalog
  `content`, immediately after the last block belonging to idea `num` and before
  the next unrelated `##`/`###` header.

  Returns `{:ok, new_content}`, `{:already_present, content}` (idempotent guard —
  the exact `### Task N - Vn -` header already exists), or
  `{:error, :base_not_found}` if idea `num` has no base line.
  """
  @spec insert_variation(String.t(), integer(), String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:already_present, String.t()} | {:error, :base_not_found}
  def insert_variation(content, num, vnum, name, desc) do
    header = "### Task #{num} - #{vnum} - #{name}"
    present_re = ~r/^###\s+Task\s+#{num}\s+-\s+#{Regex.escape(vnum)}\s+-\s+/m

    cond do
      Regex.match?(present_re, content) ->
        {:already_present, content}

      true ->
        lines = String.split(content, "\n")

        case base_index(lines, num) do
          nil ->
            {:error, :base_not_found}

          bi ->
            insert_at = insertion_point(lines, num, bi)
            block = ["", header, String.trim_trailing(desc)]
            {before, rest} = Enum.split(lines, insert_at)
            {:ok, Enum.join(before ++ block ++ rest, "\n")}
        end
    end
  end

  @doc """
  Insert an accepted variation entry into the on-disk catalog at `cfg.tasks_md`,
  unless `cfg.dry_run` is set. Returns the outcome of `insert_variation/5`.
  """
  @spec insert_variation!(Config.t(), integer(), String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:already_present, String.t()} | {:error, :base_not_found}
  def insert_variation!(%Config{} = cfg, num, vnum, name, desc) do
    content = File.read!(cfg.tasks_md)
    result = insert_variation(content, num, vnum, name, desc)

    case result do
      {:ok, new_content} when not cfg.dry_run ->
        File.write!(cfg.tasks_md, new_content)
        result

      _ ->
        result
    end
  end

  @doc """
  Heal any variation directory (`NNN_00{2,3,4}_*_01`) that lacks its
  `### Task N - Vn - Name` entry in `tasks.md` — e.g. one orphaned by a crash in the
  window between promoting the directory and inserting its catalog line.

  Insert-only and idempotent: a variation that already has an entry is a no-op
  (`insert_variation/5`'s guard), and nothing existing is ever modified. The name is
  recovered from the directory slug and the description from the first paragraph of the
  variation's `prompt.md`. Returns the number of entries inserted.
  """
  @spec reconcile_variations!(Config.t()) :: non_neg_integer()
  def reconcile_variations!(%Config{} = cfg) do
    "#{cfg.tasks_dir}/*_01"
    |> Path.wildcard()
    |> Enum.filter(&File.dir?/1)
    |> Enum.map(&variation_ref/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(0, fn %{num: num, vnum: vnum, name: name, desc: desc}, count ->
      case insert_variation!(cfg, num, vnum, name, desc) do
        {:ok, _} -> count + 1
        _ -> count
      end
    end)
  end

  # A variation `_01` dir (b in 2..4) → the fields needed to (re)catalog it, or nil.
  defp variation_ref(dir) do
    parts = dir |> Path.basename() |> String.split("_")

    with [a, b | rest] when rest != [] <- parts,
         "01" <- List.last(parts),
         {num, ""} <- Integer.parse(a),
         {bnum, ""} <- Integer.parse(b),
         true <- bnum in 2..4 do
      slug = rest |> Enum.drop(-1) |> Enum.join("_")

      %{
        num: num,
        vnum: "V#{bnum - 1}",
        name: slug |> String.replace("_", " ") |> title_case(),
        desc: prompt_first_paragraph(Path.join(dir, "prompt.md"), slug)
      }
    else
      _ -> nil
    end
  end

  defp title_case(str) do
    str |> String.split(" ", trim: true) |> Enum.map_join(" ", &String.capitalize/1)
  end

  # First non-blank, non-heading line of prompt.md (a reasonable catalog blurb), or the
  # humanized slug when prompt.md is missing/empty.
  defp prompt_first_paragraph(path, fallback_slug) do
    with {:ok, body} <- File.read(path),
         line when is_binary(line) <-
           body
           |> String.split("\n")
           |> Enum.map(&String.trim/1)
           |> Enum.find(&(&1 != "" and not String.starts_with?(&1, "#"))) do
      line
    else
      _ -> String.replace(fallback_slug, "_", " ")
    end
  end

  defp base_index(lines, num) do
    Enum.find_index(lines, fn line ->
      case Regex.run(@base_re, line) do
        [_, n, _] -> String.to_integer(n) == num
        _ -> false
      end
    end)
  end

  # Point just after the last content line of idea `num`'s region (its base line
  # and any `### Task num -` variation blocks), skipping back over trailing blanks.
  defp insertion_point(lines, num, bi) do
    region_end = region_end(lines, num, bi)

    last_content =
      Enum.reduce_while((region_end - 1)..bi//-1, region_end, fn i, _ ->
        if String.trim(Enum.at(lines, i)) == "",
          do: {:cont, i},
          else: {:halt, i + 1}
      end)

    last_content
  end

  # First index after `bi` that is a ##/### header NOT belonging to idea `num`.
  defp region_end(lines, num, bi) do
    total = length(lines)

    Enum.reduce_while((bi + 1)..total//1, total, fn i, _ ->
      cond do
        i >= total -> {:halt, total}
        belongs?(Enum.at(lines, i), num) -> {:cont, total}
        Regex.match?(@header_re, Enum.at(lines, i)) -> {:halt, i}
        true -> {:cont, total}
      end
    end)
  end

  defp belongs?(line, num) do
    case Regex.run(@variation_re, line) do
      [_, n, _, _] -> String.to_integer(n) == num
      _ -> false
    end
  end
end
