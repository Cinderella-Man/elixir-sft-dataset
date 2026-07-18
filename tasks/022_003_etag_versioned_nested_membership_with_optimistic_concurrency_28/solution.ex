  @doc """
  Atomically adds a member only if all preconditions hold, in this order:

    1. team must exist, else `{:error, :not_found}`;
    2. `expected_version` must equal the current version, else `{:error, :stale}`;
    3. the user must not already be a member, else `{:error, :conflict}`;
    4. otherwise append the user, bump the version, and return
       `{:ok, user_id, new_version}`.
  """
  @spec add_member_safe(server(), String.t(), String.t(), integer()) ::
          {:ok, String.t(), non_neg_integer()}
          | {:error, :not_found | :stale | :conflict}
  def add_member_safe(server, team_id, user_id, expected_version) do
    GenServer.call(server, {:add_member_safe, team_id, user_id, expected_version})
  end