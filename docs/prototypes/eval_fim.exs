# FIM evaluator prototype: reconstruct full module from prompt skeleton + candidate function,
# then run the PARENT (_01) task's harness against it.
[fim_dir | rest] = System.argv()
cand_file = case rest do [f|_]->f; []->Path.join(fim_dir,"solution.ex") end
base = Path.basename(fim_dir)                    # e.g. 001_001_rate_limiter_03
parent = (base |> String.split("_") |> Enum.drop(-1) |> Enum.join("_")) <> "_01"
parent_dir = Path.join("tasks", parent)
harness = Path.join(parent_dir, "test_harness.exs")

# 1. extract the elixir skeleton fence from prompt.md
prompt = File.read!(Path.join(fim_dir, "prompt.md"))
skeleton =
  case Regex.run(~r/```elixir\n(.*?)\n```/s, prompt) do
    [_, code] -> code
    _ -> raise "no elixir fence in prompt.md"
  end
candidate = File.read!(cand_file)

# 2. splice candidate into the skeleton at the TODO marker
lines = String.split(skeleton, "\n")
marker_idx = Enum.find_index(lines, &(&1 =~ ~r/#\s*TODO/i)) || raise "no TODO marker"
marker_line = Enum.at(lines, marker_idx)
after_marker = Regex.replace(~r/^\s*#\s*TODO:?/i, marker_line, "") |> String.trim()

{lo, hi} =
  if after_marker == "" do
    # Case A: stub-body. Find enclosing def (up) and its matching `end` (down).
    def_idx = marker_idx |> then(fn i ->
      Enum.reduce_while((i-1)..0//-1, nil, fn j, _ ->
        if Enum.at(lines, j) =~ ~r/^\s*(def|defp|defmacro|defmacrop)\s/, do: {:halt, j}, else: {:cont, nil}
      end)
    end)
    def_indent = Regex.run(~r/^(\s*)/, Enum.at(lines, def_idx)) |> hd()
    end_idx = Enum.reduce_while((marker_idx+1)..(length(lines)-1), nil, fn j, _ ->
      if Enum.at(lines, j) == def_indent <> "end", do: {:halt, j}, else: {:cont, nil}
    end)
    {def_idx, end_idx}
  else
    # Case B: placeholder line replaces the whole function.
    {marker_idx, marker_idx}
  end

reconstructed =
  (Enum.slice(lines, 0, lo) ++ [candidate] ++ Enum.slice(lines, (hi+1)..-1//1))
  |> Enum.join("\n")

tmp = Path.join(System.tmp_dir!(), "fim_#{System.unique_integer([:positive])}.ex")
File.write!(tmp, reconstructed)

result =
  try do
    Code.compile_file(tmp)
    ExUnit.start(autorun: false)
    Code.compile_file(harness)
    res = ExUnit.run()
    %{compiled: true, splice_case: (if after_marker=="", do: "A_stub_body", else: "B_placeholder_line"),
      tests_total: res.total, tests_failed: res.failures, tests_excluded: res.excluded}
  rescue
    e -> %{compiled: false, error: Exception.message(e) |> String.slice(0,200)}
  end
File.rm(tmp)
IO.puts(:json.encode(Map.merge(%{fim: base, parent: parent}, result)))
