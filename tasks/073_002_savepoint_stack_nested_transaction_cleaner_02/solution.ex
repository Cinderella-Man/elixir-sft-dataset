def rollback_to(name) when is_binary(name) do
  case get_state() do
    nil ->
      {:error, :not_started}

    %{repo: repo, stack: stack} = state ->
      if name in stack do
        try do
          repo.query!(repo, "ROLLBACK TO SAVEPOINT #{name}", [])
          new_stack = Enum.drop_while(stack, fn n -> n != name end)
          put_state(%{state | stack: new_stack})
          {:ok, name}
        rescue
          e -> {:error, Exception.message(e)}
        end
      else
        {:error, {:no_such_savepoint, name}}
      end
  end
end