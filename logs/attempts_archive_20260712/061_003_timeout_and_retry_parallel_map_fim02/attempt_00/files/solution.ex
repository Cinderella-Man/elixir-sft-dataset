  defp start_attempt(parent, func, elem, idx, attempts_left, timeout) do
    ref = make_ref()

    {pid, mon} =
      spawn_monitor(fn ->
        result =
          try do
            {:ok, func.(elem)}
          rescue
            e -> {:error, {:exception, e}}
          catch
            :exit, r -> {:error, {:exit, r}}
            :throw, t -> {:error, {:throw, t}}
          end

        send(parent, {ref, result})
      end)

    timer = Process.send_after(parent, {:timeout, ref}, timeout)
    {ref, {pid, mon, idx, elem, attempts_left, timer}}
  end