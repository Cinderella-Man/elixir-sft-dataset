defp start_task(key, func, from, key_state) do
  parent = self()
  ref = make_ref()

  Task.start(fn ->
    result =
      try do
        case func.() do
          {:ok, _} = ok -> ok
          {:error, _} = err -> err
          other -> {:ok, other}
        end
      rescue
        exception -> {:error, {:exception, exception}}
      end

    send(parent, {:task_done, key, ref, result})
  end)

  %{
    key_state
    | running: key_state.running + 1,
      tasks: Map.put(key_state.tasks, ref, from)
  }
end