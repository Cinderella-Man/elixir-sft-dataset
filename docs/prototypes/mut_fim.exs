# Mutation check: replace the FIM target's body(ies) with `raise`, splice, run parent harness.
# Expect tests to FAIL (target is exercised). If they PASS, the FIM is UNDER-TESTED.
[fim_dir] = System.argv()
base = Path.basename(fim_dir)
parent = (base |> String.split("_") |> Enum.drop(-1) |> Enum.join("_")) <> "_01"
harness = Path.join(["tasks", parent, "test_harness.exs"])
prompt = File.read!(Path.join(fim_dir, "prompt.md"))
[_, skeleton] = Regex.run(~r/```elixir\n(.*?)\n```/s, prompt)
ref = File.read!(Path.join(fim_dir, "solution.ex"))

# --- mutate: every def/defp clause body -> raise("MUTATION") ---
mutant =
  try do
    ref
    |> Code.string_to_quoted!()
    |> Macro.prewalk(fn
      {d, m, [head, kw]} when d in [:def, :defp] and is_list(kw) ->
        if Keyword.has_key?(kw, :do), do: {d, m, [head, [do: quote(do: raise("MUTATION"))]]}, else: {d, m, [head, kw]}
      o -> o
    end)
    |> Macro.to_string()
  rescue _ -> "raise \"MUTATION\"" end

lines = String.split(skeleton, "\n")
mi = Enum.find_index(lines, &(&1 =~ ~r/#\s*TODO/i))
after_m = Regex.replace(~r/^\s*#\s*TODO:?/i, Enum.at(lines, mi), "") |> String.trim()
{lo, hi} =
  if after_m == "" do
    di = Enum.reduce_while((mi-1)..0//-1, nil, fn j,_ -> if Enum.at(lines,j)=~~r/^\s*(def|defp|defmacro|defmacrop)\s/, do: {:halt,j}, else: {:cont,nil} end)
    ind = Regex.run(~r/^(\s*)/, Enum.at(lines,di)) |> hd()
    ei = Enum.reduce_while((mi+1)..(length(lines)-1), nil, fn j,_ -> if Enum.at(lines,j)==ind<>"end", do: {:halt,j}, else: {:cont,nil} end)
    {di, ei}
  else {mi, mi} end
recon = (Enum.slice(lines,0,lo) ++ [mutant] ++ Enum.slice(lines,(hi+1)..-1//1)) |> Enum.join("\n")
tmp = Path.join(System.tmp_dir!(), "mut_#{System.unique_integer([:positive])}.ex")
File.write!(tmp, recon)
res =
  try do
    Code.compile_file(tmp); ExUnit.start(autorun: false); Code.compile_file(harness); ExUnit.run()
  rescue e -> %{total: -1, failures: -1, err: Exception.message(e) |> String.slice(0,80)} end
File.rm(tmp)
verdict = cond do
  Map.get(res,:err) -> "MUTANT_WONT_COMPILE"       # acceptable-ish (mutation broke syntax)
  res.total > 0 and res.failures > 0 -> "GOOD_exercised"
  true -> "UNDER_TESTED_mutant_passed"
end
IO.puts(:json.encode(%{fim: base, verdict: verdict, total: res.total, failures: res.failures}))
