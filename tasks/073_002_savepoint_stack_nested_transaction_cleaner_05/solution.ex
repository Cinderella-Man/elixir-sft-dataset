  @doc "Currently-active savepoint names, oldest first."
  @spec active_savepoints() :: [String.t()]
  def active_savepoints do
    case get_state() do
      nil -> []
      %{stack: stack} -> Enum.reverse(stack)
    end
  end