@impl GenServer
def handle_call({:execute, key, func}, from, state) do
  case Map.fetch(state, key) do
    # -----------------------------------------------------------------------
    # No in-flight execution for this key — spawn one and register caller.
    # -----------------------------------------------------------------------
    :error ->
      parent = self()

      Task.start(fn ->
        result =
          try do
            case func.() do
              {:ok, _} = ok      -> ok
              {:error, _} = err  -> err
              other              -> {:ok, other}
            end
          rescue
            exception -> {:error, {:exception, exception}}
          end

        send(parent, {:task_done, key, result})
      end)

      {:noreply, Map.put(state, key, [from])}

    # -----------------------------------------------------------------------
    # Execution already in flight — join the wait list, do not call func.
    # -----------------------------------------------------------------------
    {:ok, callers} ->
      {:noreply, Map.put(state, key, callers ++ [from])}
  end
end