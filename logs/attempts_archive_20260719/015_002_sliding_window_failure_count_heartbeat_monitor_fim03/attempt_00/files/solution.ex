  @spec maybe_schedule(term(), pos_integer() | :manual, non_neg_integer()) :: :ok
  defp maybe_schedule(name, interval, epoch) when is_integer(interval) do
    Process.send_after(self(), {:tick, name, epoch}, interval)
    :ok
  end

  defp maybe_schedule(_name, :manual, _epoch), do: :ok