defmodule EvalTask.Discovery do
  @moduledoc """
  Enumerate every gradable task under `tasks/`, classifying each by SHAPE from its
  content (not its location): single-file, multi-file (`<file>` bundle), or FIM
  (a `_02+` subtask with no harness of its own). This is what lets `run_all` see
  FIM subtasks and multi-file bundles, which older location-based discovery missed.
  """

  @type task :: %{
          name: String.t(),
          dir: String.t(),
          shape: :single | :fim | :multifile,
          solution: String.t(),
          found: boolean()
        }

  @doc """
  All tasks, using `solution_filename` as the candidate solution in each dir.
  `found: true` when that solution file exists.
  """
  @spec all(String.t()) :: [task()]
  def all(solution_filename \\ "solution.ex") do
    for dir <- Path.wildcard("tasks/*"), File.dir?(dir) do
      annotate(dir, solution_filename)
    end
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.name)
  end

  defp annotate(dir, sol_name) do
    sol = Path.join(dir, sol_name)
    has_harness = File.regular?(Path.join(dir, "test_harness.exs"))
    found = File.regular?(sol)

    cond do
      # No harness of its own → a FIM subtask (parent _01 has the harness).
      not has_harness ->
        if EvalTask.Fim.fim_dir?(dir), do: task(dir, :fim, sol, found), else: nil

      # Has a harness → single-file or multi-file, decided by the solution's content.
      found and EvalTask.Bundle.bundle?(File.read!(sol)) ->
        task(dir, :multifile, sol, found)

      # A shipped manifest.exs also marks a multi-file task (covers unsolved ones).
      File.regular?(Path.join(dir, "manifest.exs")) ->
        task(dir, :multifile, sol, found)

      true ->
        task(dir, :single, sol, found)
    end
  end

  defp task(dir, shape, sol, found),
    do: %{name: Path.basename(dir), dir: dir, shape: shape, solution: sol, found: found}
end
