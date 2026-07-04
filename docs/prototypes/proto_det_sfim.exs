# Prototype §4.6: DETERMINISTIC code-FIM minting (no LLM).
# Carve a function's source span from a solved module (tfim-style line scanning),
# blank the body to "# TODO", build a FIM dir, and grade it with the REAL evaluator.
#
# Gold = the verbatim source slice (incl. multi-clause + @impl); skeleton = module
# with the body of every clause of that function replaced by "# TODO".

defmodule DetSfim do
  # Find contiguous span of all clauses of {name} at 2-space indent, including
  # attached @impl/@doc/@spec lines directly above.
  def carve(src, fun_name) do
    lines = String.split(src, "\n")
    re = ~r/^  defp? #{Regex.escape(fun_name)}[\(\s]/

    idxs = for {l, i} <- Enum.with_index(lines), Regex.match?(re, l), do: i
    if idxs == [], do: raise("function #{fun_name} not found at 2-space indent")

    spans =
      for start <- idxs do
        {a, _} = attach_attrs(lines, start)
        b = scan_end(lines, start)
        {a, b}
      end

    {lo, _} = hd(spans)
    {_, hi} = List.last(spans)
    gold = lines |> Enum.slice(lo..hi) |> Enum.join("\n")

    skeleton_lines =
      spans
      |> Enum.reverse()
      |> Enum.reduce(lines, fn {a, b}, acc ->
        # keep the def head line(s) up to `do`, blank the body
        head_end = Enum.find(a..b, fn i -> String.ends_with?(String.trim_trailing(Enum.at(acc, i)), " do") end)
        head = Enum.slice(acc, a..head_end)
        List.replace_at(acc, a, Enum.join(head ++ ["    # TODO", "  end"], "\n"))
        |> strip_range(a + 1, b)
      end)

    {gold, Enum.join(skeleton_lines, "\n")}
  end

  defp strip_range(lines, a, b) do
    lines |> Enum.with_index() |> Enum.reject(fn {_, i} -> i >= a and i <= b end) |> Enum.map(&elem(&1, 0))
  end

  defp attach_attrs(lines, start) do
    a =
      Enum.reduce_while((start - 1)..0//-1, start, fn i, acc ->
        t = String.trim(Enum.at(lines, i))
        if String.starts_with?(t, ["@impl", "@doc", "@spec"]) or t == "",
          do: {:cont, if(t == "", do: acc, else: i)},
          else: {:halt, acc}
      end)

    {a, start}
  end

  defp scan_end(lines, start) do
    Enum.find((start + 1)..(length(lines) - 1), fn i -> Enum.at(lines, i) == "  end" end)
  end
end

repo = File.cwd!()
scratch = Path.join(System.tmp_dir!(), "det_sfim_proto")
File.rm_rf!(scratch)
File.mkdir_p!(scratch)

parent_name = "002_001_circuit_breaker_01"
parent_src = Path.join([repo, "tasks", parent_name])
parent_dst = Path.join(scratch, parent_name)
File.mkdir_p!(parent_dst)
for f <- ~w(solution.ex test_harness.exs prompt.md),
    do: File.cp!(Path.join(parent_src, f), Path.join(parent_dst, f))

src = File.read!(Path.join(parent_dst, "solution.ex"))

# target: handle_call (multi-clause GenServer callback — the hard case)
{gold, skeleton} = DetSfim.carve(src, "handle_call")

fim_dir = Path.join(scratch, "002_001_circuit_breaker_99")
File.mkdir_p!(fim_dir)

prompt = """
# Fill in the middle: implement `handle_call/3`

Below is a complete Elixir module with the body of `handle_call/3` removed
(marked `# TODO`). Implement just that function so the module behaves as documented.

```elixir
#{skeleton}
```
"""

File.write!(Path.join(fim_dir, "prompt.md"), prompt)
File.write!(Path.join(fim_dir, "solution.ex"), gold)

IO.puts("gold: #{length(String.split(gold, "\n"))} lines; skeleton TODO count: " <>
  "#{length(String.split(skeleton, "# TODO")) - 1}")

{out, _} =
  System.cmd("elixir", [Path.join(repo, "scripts/eval_task.exs"), fim_dir],
    cd: repo, stderr_to_stdout: true)

res = out |> String.split("\n", trim: true) |> List.last() |> Jason.decode!()

IO.puts(
  "shape=#{res["shape"]} compiled=#{res["compiled"]} " <>
    "passed=#{res["tests_passed"]}/#{res["tests_total"]} failed=#{res["tests_failed"]} " <>
    "overall=#{res["score"] && res["score"]["overall"]}"
)

IO.puts("PROTOTYPE #{if res["tests_failed"] == 0 and res["tests_passed"] > 0, do: "VIABLE", else: "FAILED — inspect #{fim_dir}"}")
