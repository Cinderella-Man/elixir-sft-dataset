  @doc """
  Removes `element` from the set.

  All current tags for the element are moved to the tombstones set. Raises
  `ArgumentError` if the element is not currently a member.

  Returns `:ok`.
  """
  @spec remove(server(), element()) :: :ok
  def remove(server, element) do
    case GenServer.call(server, {:remove, element}) do
      :ok ->
        :ok

      {:error, :not_a_member} ->
        raise ArgumentError,
              "cannot remove element #{inspect(element)}: not a current member"
    end
  end