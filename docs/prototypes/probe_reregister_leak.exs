# Probe: does re-registering a service leak the previous automatic tick chain?
# Expectation if the bug is real: after re-register, checks arrive ~2x per interval.
[solution_path] = System.argv()
Code.compile_string(File.read!(solution_path))

{:ok, server} = Monitor.start_link([])
{:ok, counter} = Agent.start_link(fn -> 0 end)
check = fn -> Agent.update(counter, &(&1 + 1)) end
counted_check = fn ->
  check.()
  :ok
end

interval = 50

# Single registration: count checks over a fixed window.
:ok = Monitor.register(server, "svc", counted_check, interval)
Process.sleep(500)
single = Agent.get(counter, & &1)

# Re-register the SAME name (replace semantics). If the old chain leaks, the
# tick rate doubles.
Agent.update(counter, fn _ -> 0 end)
:ok = Monitor.register(server, "svc", counted_check, interval)
Process.sleep(500)
double = Agent.get(counter, & &1)

IO.puts("checks in 500ms after first registration:  #{single}")
IO.puts("checks in 500ms after re-registration:     #{double}")

ratio = if single > 0, do: double / single, else: :undefined
IO.puts("ratio: #{inspect(ratio)}")

if is_float(ratio) and ratio > 1.6 do
  IO.puts("VERDICT: BUG CONFIRMED — re-registration leaks the previous tick chain")
else
  IO.puts("VERDICT: not confirmed")
end
