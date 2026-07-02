  defp do_take([], state), do: {:none, %{state | available: []}}

  defp do_take([conn | rest], state) do
    if state.validate.(conn) do
      {:ok, conn, %{state | available: rest}}
    else
      state.destroy.(conn)
      do_take(rest, %{state | total: state.total - 1})
    end
  end