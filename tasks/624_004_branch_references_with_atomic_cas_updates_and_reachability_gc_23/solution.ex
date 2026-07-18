  def update_branch(server, name, expected_hash, new_hash)
      when is_binary(name) and is_binary(expected_hash) and is_binary(new_hash) do
    GenServer.call(server, {:update_branch, name, expected_hash, new_hash})
  end