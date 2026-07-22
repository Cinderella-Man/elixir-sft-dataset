  @spec apply_result(map(), :ok | {:error, term()}) :: map()
  defp apply_result(node, :ok) do
    own_status = if node.own_status == :down, do: :up, else: node.own_status
    %{node | fail_count: 0, own_status: own_status}
  end

  defp apply_result(node, {:error, _reason}) do
    count = node.fail_count + 1

    own_status =
      if count >= node.threshold and node.own_status == :up do
        :down
      else
        node.own_status
      end

    %{node | fail_count: count, own_status: own_status}
  end