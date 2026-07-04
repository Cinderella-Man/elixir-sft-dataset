# Prototype §4.1: measure REAL tfim yield using the production carver
# (GenTask.TestFim.test_blocks/1) across every harness-bearing task.

harnesses = Path.wildcard("tasks/*_01/test_harness.exs")

counts =
  for h <- harnesses do
    src = File.read!(h)
    blocks = GenTask.TestFim.test_blocks(src)
    {Path.basename(Path.dirname(h)), length(blocks)}
  end

vals = counts |> Enum.map(&elem(&1, 1)) |> Enum.sort()
n = length(vals)
med = Enum.at(vals, div(n, 2))
total = Enum.sum(vals)

existing = Path.wildcard("tasks/tfim_*") |> length()

cap = fn c -> counts |> Enum.map(fn {_, k} -> min(k, c) end) |> Enum.sum() end

IO.puts("harness-bearing _01 dirs: #{n}")
IO.puts("carvable test blocks (production carver): total=#{total} med=#{med} " <>
  "min=#{List.first(vals)} max=#{List.last(vals)}")
IO.puts("zero-carvable harnesses (describe-nested etc.): #{Enum.count(vals, &(&1 == 0))}")
IO.puts("existing tfim dirs: #{existing}")
IO.puts("yield at cap 3:  #{cap.(3)}")
IO.puts("yield at cap 10: #{cap.(10)}")
IO.puts("yield at cap 15: #{cap.(15)}")
IO.puts("yield uncapped:  #{total}")
IO.puts("NOTE: actual accepts also pass the isolation-kill gate, so treat these as upper bounds.")
