  def savepoint(name) when is_binary(name) do
    if Regex.match?(@valid_identifier, name) do
      case get_state() do
        nil ->
          {:error, :not_started}

        %{repo: repo, stack: stack} = state ->
          try do
            repo.query!(repo, "SAVEPOINT #{name}", [])
            put_state(%{state | stack: [name | stack]})
            {:ok, name}
          rescue
            e -> {:error, Exception.message(e)}
          end
      end
    else
      {:error, {:invalid_name, name}}
    end
  end

  def savepoint(other), do: {:error, {:invalid_name, other}}