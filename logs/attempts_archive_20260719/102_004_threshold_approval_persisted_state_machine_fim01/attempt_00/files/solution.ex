  defp next_state(:draft, :submit, _approvals, _required), do: {:ok, :in_review, 0}

  defp next_state(:in_review, :approve, approvals, required) do
    new_approvals = approvals + 1

    if new_approvals >= required do
      {:ok, :approved, new_approvals}
    else
      {:ok, :in_review, new_approvals}
    end
  end

  defp next_state(:in_review, :reject, approvals, _required),
    do: {:ok, :rejected, approvals}

  defp next_state(:draft, :withdraw, approvals, _required),
    do: {:ok, :withdrawn, approvals}

  defp next_state(:in_review, :withdraw, approvals, _required),
    do: {:ok, :withdrawn, approvals}

  defp next_state(_state, _event, _approvals, _required), do: :error