  @doc """
  Creates a new cumulative leaderboard backed by a public ETS set named `board_name`.
  """
  @spec new(atom()) :: {:ok, board()}
  def new(board_name) when is_atom(board_name) do
    tid =
      :ets.new(board_name, [
        :set,
        :public,
        :named_table,
        read_concurrency: true,
        write_concurrency: true
      ])

    {:ok, tid}
  end