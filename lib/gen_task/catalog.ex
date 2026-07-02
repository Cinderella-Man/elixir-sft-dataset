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
            needs_variations?: boolean(),
            needs_fim?: boolean()
          }
    defstruct [:dir, :task_id, :num, :b, :base?, needs_variations?: false, needs_fim?: false]
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
    "#{cfg.tasks_dir}/*_01"
    |> Path.wildcard()
    |> Enum.filter(&File.dir?/1)
    |> Enum.sort()
    |> Enum.map(&seed(&1, cfg))
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&(&1.needs_variations? or &1.needs_fim?))
    |> Enum.filter(&in_scope?(&1.num, cfg))
  end

  defp seed(dir, %Config{} = cfg) do
    base = Path.basename(dir)
    parts = String.split(base, "_")

    with [a, b | _] <- parts,
         {num, ""} <- Integer.parse(a),
         {bnum, ""} <- Integer.parse(b),
         "01" <- List.last(parts) do
      base? = bnum == 1

      %Seed{
        dir: dir,
        task_id: base,
        num: num,
        b: bnum,
        base?: base?,
        needs_variations?: base? and not has_variations?(cfg.tasks_dir, a),
        needs_fim?: not has_fim?(cfg.tasks_dir, a, b)
      }
    else
      _ -> nil
    end
  end

  defp has_variations?(tasks_dir, a) do
    "#{tasks_dir}/#{a}_002_*_01"
    |> Path.wildcard()
    |> Enum.any?(&File.dir?/1)
  end

  defp has_fim?(tasks_dir, a, b) do
    "#{tasks_dir}/#{a}_#{b}_*"
    |> Path.wildcard()
    |> Enum.any?(fn d ->
      File.dir?(d) and fim_subtask?(Path.basename(d))
    end)
  end

  # A FIM subtask directory ends in a subtask index >= 2 (e.g. `_02`, `_10`).
  defp fim_subtask?(basename) do
    case Integer.parse(List.last(String.split(basename, "_"))) do
      {n, ""} -> n >= 2
      _ -> false
    end
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
