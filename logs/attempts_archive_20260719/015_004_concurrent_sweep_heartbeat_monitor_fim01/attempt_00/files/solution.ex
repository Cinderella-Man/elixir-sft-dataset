  # Compute the new service state, plus whether the status changed.
  @spec apply_result(map(), :ok | :error) :: {map(), boolean(), status()}
  defp apply_result(%{status: st} = svc, :ok) do
    {%{svc | status: :up, count: 0}, st == :down, :up}
  end

  defp apply_result(%{status: st, count: c, threshold: t} = svc, :error) do
    new_count = c + 1

    if new_count >= t and st == :up do
      {%{svc | status: :down, count: new_count}, true, :down}
    else
      {%{svc | count: new_count}, false, st}
    end
  end