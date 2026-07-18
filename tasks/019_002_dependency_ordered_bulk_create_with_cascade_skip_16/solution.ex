  @doc """
  Start the backing `Agent`, registered under this module's name.
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(_ \\ []) do
    Agent.start_link(fn -> %{items: %{}, next_id: 1} end, name: __MODULE__)
  end