# Prototype §4.4: de-documentation pairs.
# Strip @moduledoc/@doc/@spec (line-scan, heredoc-aware), verify stripped module
# still compiles and passes its harness on 3 sample tasks.

defmodule DeDoc do
  @doc_attrs ~w(@moduledoc @doc @typedoc)
  # @spec/@type can span lines until parens/brackets balance

  def strip(src) do
    src
    |> String.split("\n")
    |> walk([], :code)
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  defp walk([], acc, _), do: acc

  defp walk([line | rest], acc, :code) do
    t = String.trim_leading(line)

    cond do
      Enum.any?(@doc_attrs, &String.starts_with?(t, &1 <> " ")) or
          Enum.any?(@doc_attrs, &(t == &1)) ->
        cond do
          String.contains?(t, ~s(""")) and not closed_heredoc?(t) ->
            walk(rest, acc, :heredoc)

          true ->
            # single-line (@doc false, @doc "...") — drop it
            walk(rest, acc, :code)
        end

      String.starts_with?(t, "@spec ") ->
        if balanced?(t), do: walk(rest, acc, :code), else: walk(rest, acc, :spec)

      true ->
        walk(rest, [line | acc], :code)
    end
  end

  defp walk([line | rest], acc, :heredoc) do
    if String.trim(line) |> String.starts_with?(~s(""")),
      do: walk(rest, acc, :code),
      else: walk(rest, acc, :heredoc)
  end

  defp walk([line | rest], acc, :spec) do
    # continue swallowing until the accumulated spec balances (crude: line ends without trailing comma/open)
    if balanced?(line), do: walk(rest, acc, :code), else: walk(rest, acc, :spec)
  end

  # a heredoc opener that also closes on the same line: @doc """x"""
  defp closed_heredoc?(t) do
    length(String.split(t, ~s("""))) >= 3
  end

  defp balanced?(line) do
    opens = count(line, ["(", "[", "{"])
    closes = count(line, [")", "]", "}"])
    not String.ends_with?(String.trim_trailing(line), [",", "|", "::", "when"]) and opens <= closes
  end

  defp count(line, tokens),
    do: Enum.sum(for t <- tokens, do: length(String.split(line, t)) - 1)
end

repo = File.cwd!()
scratch = Path.join(System.tmp_dir!(), "dedoc_proto")
File.rm_rf!(scratch)

samples = ~w(
  tasks/002_001_circuit_breaker_01
  tasks/076_001_trie_01
  tasks/100_001_totp_time_based_one_time_password_implementation_01
)

grade = fn dir, sol ->
  {out, _} =
    System.cmd("elixir", [Path.join(repo, "scripts/eval_task.exs"), dir, sol],
      cd: repo, stderr_to_stdout: true)

  out |> String.split("\n", trim: true) |> List.last() |> Jason.decode!()
end

for task <- samples do
  src = File.read!(Path.join([repo, task, "solution.ex"]))
  stripped = DeDoc.strip(src)

  dir = Path.join(scratch, Path.basename(task))
  File.mkdir_p!(dir)
  File.cp!(Path.join([repo, task, "test_harness.exs"]), Path.join(dir, "test_harness.exs"))
  File.write!(Path.join(dir, "solution.ex"), stripped)

  res = grade.(dir, "solution.ex")
  removed = length(String.split(src, "\n")) - length(String.split(stripped, "\n"))

  # analysis score should DROP on the stripped version (that's the training signal)
  IO.puts(
    "#{Path.basename(task)}: stripped #{removed} lines | compiled=#{res["compiled"]} " <>
      "passed=#{res["tests_passed"]}/#{res["tests_total"]} failed=#{res["tests_failed"]} " <>
      "analysis=#{res["score"]["analysis_score"]} overall=#{res["score"]["overall"]}"
  )
end

IO.puts("\n(gold = original solution: analysis 1.0; stripped must be green with lower analysis)")
