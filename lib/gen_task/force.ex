defmodule GenTask.Force do
  @moduledoc """
  The `--force` family wipe (Kamil, 2026-07-15 — T1.9): delete EVERYTHING a base
  idea's family put on disk, so a plain loop run regenerates it from the catalog
  idea alone. This is the instrument for the loop-parity experiment (docs/12 §5.5):
  wipe one family, regenerate it, and `git diff` shows exactly what quality the
  loop produces versus what the catch-up campaign retrofitted.

  What a family wipe removes, for idea number `n` (padded to `NNN`):

    * every `tasks/NNN_*` directory — the base `_01`, all variations, all FIM
      subtasks;
    * every derived directory: `tasks/wt_NNN_*`, `tfim_NNN_*`, `bugfix_NNN_*`,
      `adapt_NNN_*`, `repair_NNN_*`;
    * the idea's `### Task n - Vx - …` variation entries in `tasks.md` (they
      describe the DELETED variations; the regenerated ones insert their own);
    * the family's `logs/errors/*.log` and `logs/quarantine/*` blockers (they
      gate retries of the OLD generation, which no longer exists).

  Deliberately NOT removed: the sha-keyed ledgers (`seed_verdicts`,
  `tfim_rejected`, `bugfix_rejected`, `adapt_redgate`, `screen_blind`, `runs`,
  `usage`, `flaky`). Their rows are keyed to the deleted content's hashes, so the
  regenerated family never matches them — they stay as the audit trail of the old
  generation (HOW-WE-WORK rule 7 corollary: ledgers are permanent).

  Safety: the wipe REFUSES to run unless every target directory (and `tasks.md`)
  is fully tracked and unmodified in git — deletion must always be recoverable
  with `git checkout`. Under `GEN_DRY_RUN=1` it prints the full deletion list and
  deletes nothing.
  """

  alias GenTask.{Catalog, Config}

  @derived_prefixes ~w(wt_ tfim_ bugfix_ adapt_ repair_)

  @doc """
  Wipe `cfg.only_idea`'s family (see the moduledoc). Raises when `--force` was
  given without a single positional idea number, or when any target is not
  git-clean. Returns a report map of everything removed (or would-remove, under
  dry-run).

  `opts[:git_check]` injects the cleanliness check (`fn paths -> :ok end` in
  tests); the default is `git_clean_check!/1`.
  """
  @spec wipe!(Config.t(), keyword()) :: %{
          dirs: [String.t()],
          catalog_entries: [String.t()],
          error_logs: [String.t()],
          quarantine: [String.t()]
        }
  def wipe!(%Config{} = cfg, opts \\ []) do
    num =
      cfg.only_idea ||
        raise ArgumentError,
              "--force requires a single base idea number, e.g. " <>
                "`mix run scripts/generate.exs 15 --force` — refusing to wipe anything broader"

    git_check = Keyword.get(opts, :git_check, &git_clean_check!/1)

    dirs = family_dirs(cfg, num)
    {new_tasks_md, removed_entries} = strip_variations(File.read!(cfg.tasks_md), num)
    error_logs = family_error_logs(cfg, num)
    quarantine = family_quarantine_dirs(cfg, num)

    print_plan(cfg, num, dirs, removed_entries, error_logs, quarantine)

    if cfg.dry_run do
      IO.puts("force: DRY-RUN — nothing deleted.")
    else
      git_check.(dirs ++ [cfg.tasks_md])

      Enum.each(dirs, fn dir ->
        guard_under!(cfg.tasks_dir, dir)
        File.rm_rf!(dir)
        IO.puts("force: removed #{dir}")
      end)

      if removed_entries != [] do
        File.write!(cfg.tasks_md, new_tasks_md)

        Enum.each(
          removed_entries,
          &IO.puts("force: removed catalog entry \"#{&1}\" from #{cfg.tasks_md}")
        )
      end

      Enum.each(error_logs ++ quarantine, fn path ->
        File.rm_rf!(path)
        IO.puts("force: removed #{path}")
      end)

      IO.puts(
        "force: family #{num} wiped — the loop below regenerates it from the catalog idea. " <>
          "The old family is recoverable with `git checkout -- #{cfg.tasks_dir} #{cfg.tasks_md}`."
      )
    end

    %{
      dirs: dirs,
      catalog_entries: removed_entries,
      error_logs: error_logs,
      quarantine: quarantine
    }
  end

  @doc """
  Every on-disk directory belonging to idea `num`'s family: `NNN_*` (base,
  variations, FIM) plus the five derived prefixes (`wt_ tfim_ bugfix_ adapt_
  repair_`). Sorted.
  """
  @spec family_dirs(Config.t(), pos_integer()) :: [String.t()]
  def family_dirs(%Config{tasks_dir: tasks_dir}, num) do
    a = Catalog.pad3(num)
    patterns = ["#{a}_*" | Enum.map(@derived_prefixes, &"#{&1}#{a}_*")]

    patterns
    |> Enum.flat_map(&Path.wildcard(Path.join(tasks_dir, &1)))
    |> Enum.filter(&File.dir?/1)
    |> Enum.sort()
  end

  @doc """
  Remove idea `num`'s `### Task num - Vx - …` blocks (header through the line
  before the next `##`/`###` header) from catalog `content`. Returns
  `{new_content, removed_header_titles}`. Pure — the caller decides whether to
  write. Inverse of `GenTask.Catalog.insert_variation/5`'s insert.
  """
  @spec strip_variations(String.t(), pos_integer()) :: {String.t(), [String.t()]}
  def strip_variations(content, num) do
    header_re = ~r/^###\s+Task\s+#{num}\s+-\s+V\d+\s+-\s+(.+?)\s*$/
    any_header_re = ~r/^##/

    {kept_rev, removed_rev, _skipping?} =
      content
      |> String.split("\n")
      |> Enum.reduce({[], [], false}, fn line, {kept, removed, skipping?} ->
        cond do
          match = Regex.run(header_re, line) ->
            [_, title] = match
            {kept, [title | removed], true}

          skipping? and Regex.match?(any_header_re, line) ->
            {[line | kept], removed, false}

          skipping? ->
            {kept, removed, true}

          true ->
            {[line | kept], removed, false}
        end
      end)

    {kept_rev |> Enum.reverse() |> Enum.join("\n"), Enum.reverse(removed_rev)}
  end

  @doc "The family's `logs/errors/*.log` retry blockers (base, derived and log ids)."
  @spec family_error_logs(Config.t(), pos_integer()) :: [String.t()]
  def family_error_logs(%Config{logs_dir: logs_dir}, num) do
    a = Catalog.pad3(num)
    patterns = ["#{a}_*.log" | Enum.map(@derived_prefixes, &"#{&1}#{a}_*.log")]

    patterns
    |> Enum.flat_map(&Path.wildcard(Path.join([logs_dir, "errors", &1])))
    |> Enum.sort()
  end

  @doc "The family's `logs/quarantine/*` dirs (they block the idea from re-entering the loop)."
  @spec family_quarantine_dirs(Config.t(), pos_integer()) :: [String.t()]
  def family_quarantine_dirs(%Config{logs_dir: logs_dir}, num) do
    a = Catalog.pad3(num)

    [logs_dir, "quarantine", "#{a}_*"]
    |> Path.join()
    |> Path.wildcard()
    |> Enum.sort()
  end

  @doc """
  Raise unless every existing path in `paths` is fully tracked and unmodified in
  git (so `git checkout` can always restore what the wipe deletes). Two probes:
  `git status --porcelain` must be silent for them (no modifications, no untracked
  files), and every existing DIRECTORY must contain at least one tracked file
  (a fully ignored dir is invisible to porcelain yet unrecoverable).

  `cd` is the git worktree to run in (`nil` = the current directory — generation
  runs from the repo root); explicit in tests, which build throwaway repos.
  """
  @spec git_clean_check!([String.t()], String.t() | nil) :: :ok
  def git_clean_check!(paths, cd \\ nil) do
    existing = Enum.filter(paths, &exists_in?(cd, &1))

    case git(cd, ["status", "--porcelain", "--"] ++ existing) do
      {"", 0} ->
        :ok

      {out, 0} ->
        raise ArgumentError,
              "force: refusing to delete — these paths have uncommitted or untracked " <>
                "changes (deletion would lose work):\n#{out}Commit or stash first."

      {out, code} ->
        raise RuntimeError, "force: `git status` failed (exit #{code}): #{out}"
    end

    for dir <- existing, File.dir?(Path.expand(dir, cd || ".")) do
      case git(cd, ["ls-files", "--", dir]) do
        {"", 0} ->
          raise ArgumentError,
                "force: refusing to delete #{dir} — it contains no git-tracked files, " <>
                  "so deletion would be unrecoverable"

        {_out, 0} ->
          :ok

        {out, code} ->
          raise RuntimeError, "force: `git ls-files` failed (exit #{code}): #{out}"
      end
    end

    :ok
  end

  defp git(nil, args), do: System.cmd("git", args, stderr_to_stdout: true)
  defp git(cd, args), do: System.cmd("git", args, cd: cd, stderr_to_stdout: true)

  defp exists_in?(cd, path), do: File.exists?(Path.expand(path, cd || "."))

  # ---------------------------------------------------------------------------
  # helpers
  # ---------------------------------------------------------------------------

  defp print_plan(cfg, num, dirs, removed_entries, error_logs, quarantine) do
    IO.puts("""

    =============================================
      FORCE WIPE — idea #{num} (#{cfg.tasks_dir})
      #{length(dirs)} task dir(s), #{length(removed_entries)} tasks.md variation \
    entr#{if length(removed_entries) == 1, do: "y", else: "ies"}, \
    #{length(error_logs)} error log(s), #{length(quarantine)} quarantine dir(s)
    =============================================\
    """)

    Enum.each(dirs, &IO.puts("  will remove dir:   #{&1}"))
    Enum.each(removed_entries, &IO.puts("  will remove entry: ### Task #{num} - Vx - #{&1}"))
    Enum.each(error_logs, &IO.puts("  will remove log:   #{&1}"))
    Enum.each(quarantine, &IO.puts("  will remove dir:   #{&1}"))
  end

  # Belt-and-braces: a family dir computed by `family_dirs/2` is under the tasks
  # dir by construction; verify anyway before an `rm -rf`.
  defp guard_under!(tasks_dir, dir) do
    root = Path.expand(tasks_dir)
    expanded = Path.expand(dir)

    unless String.starts_with?(expanded, root <> "/") do
      raise ArgumentError, "force: refusing to remove a path outside #{tasks_dir}: #{dir}"
    end
  end
end
