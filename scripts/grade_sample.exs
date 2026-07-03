# Independently grade a list of task dirs (args) in-process, printing one compact line each.
# Usage: mix run scripts/grade_sample.exs <dir> [<dir> ...]
System.argv()
|> Enum.each(fn dir ->
  try do
    {json, 0} =
      System.cmd("elixir", ["scripts/eval_task.exs", dir], stderr_to_stdout: false)

    d = Jason.decode!(json)
    sc = d["score"] || %{}

    status =
      cond do
        d["skipped"] -> "SKIPPED(#{d["skipped"]})"
        d["compiled"] == false -> "NOT-COMPILED"
        (d["tests_failed"] || 0) > 0 or (d["tests_errors"] || 0) > 0 -> "TEST-FAIL"
        true -> "green"
      end

    IO.puts(
      "#{status}\t#{d["shape"]}\t#{d["tests_passed"]}/#{d["tests_total"]}\toverall=#{sc["overall"]}\t#{Path.basename(dir)}"
    )
  rescue
    e -> IO.puts("ERROR\t#{Path.basename(dir)}\t#{Exception.message(e)}")
  catch
    _, v -> IO.puts("CRASH\t#{Path.basename(dir)}\t#{inspect(v)}")
  end
end)
