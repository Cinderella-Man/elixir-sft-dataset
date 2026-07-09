defp spawn_task(parent, func, elem) do
  our_ref = make_ref()

  {_pid, mon_ref} =
    spawn_monitor(fn ->
      result =
        try do
          {:ok, func.(elem)}
        rescue
          e -> {:error, {e, __STACKTRACE__}}
        catch
          :exit, r -> {:error, r}
          :throw, t -> {:error, {:throw, t}}
        end

      send(parent, {our_ref, result})
    end)

  {our_ref, mon_ref}
end