  @doc """
  Creates a new leaderboard.  Returns `{:ok, board}` where `board` carries the
  owning server and the two table handles.
  """
  @spec new(atom()) :: {:ok, board()}
  def new(board_name) when is_atom(board_name) do
    {:ok, pid} = GenServer.start_link(__MODULE__, board_name)
    GenServer.call(pid, :board)
  end