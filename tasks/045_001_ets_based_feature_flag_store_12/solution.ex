  @doc """
  Enables `flag_name` for `percentage`% of users (0–100).

  The bucket assignment is deterministic per `{flag_name, user_id}` pair.
  Passing `0` is equivalent to `disable/1`; passing `100` is equivalent
  to `enable/1`.
  """
  @spec enable_for_percentage(atom(), 0..100) :: :ok
  def enable_for_percentage(flag_name, percentage)
      when is_integer(percentage) and percentage >= 0 and percentage <= 100 do
    GenServer.call(server(), {:set, flag_name, {:percentage, percentage}})
  end