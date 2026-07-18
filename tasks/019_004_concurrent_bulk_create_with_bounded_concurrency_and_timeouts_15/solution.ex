  @doc """
  Start the store `Agent`, registered under this module's name.
  """
  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(_ \\ []) do
    Agent.start_link(
      fn -> %{items: %{}, next_id: 1, running: 0, peak: 0} end,
      name: __MODULE__
    )
  end