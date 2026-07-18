  @doc """
  Start the backing `Agent`, registered under `#{inspect(__MODULE__)}`.
  """
  @spec start_link(keyword) :: Agent.on_start()
  def start_link(_ \\ []) do
    Agent.start_link(fn -> %{records: %{}} end, name: __MODULE__)
  end