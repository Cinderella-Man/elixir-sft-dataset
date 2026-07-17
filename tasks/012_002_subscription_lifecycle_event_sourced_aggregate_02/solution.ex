  # Create
  defp validate_command(nil, {:create, plan_name}) do
    {:ok, [%{type: :subscription_created, plan: plan_name}]}
  end

  defp validate_command(_state, {:create, _plan_name}), do: {:error, :already_exists}

  # Not Found Catch-all
  defp validate_command(nil, _command), do: {:error, :not_found}

  # Activate
  defp validate_command(%{status: :pending}, {:activate}) do
    {:ok, [%{type: :subscription_activated}]}
  end

  defp validate_command(_state, {:activate}), do: {:error, :not_pending}

  # Suspend
  defp validate_command(%{status: :active}, {:suspend, reason}) do
    {:ok, [%{type: :subscription_suspended, reason: reason}]}
  end

  defp validate_command(_state, {:suspend, _reason}), do: {:error, :not_active}

  # Cancel
  # Must fail only if already cancelled; any other existing status may cancel.
  defp validate_command(%{status: :cancelled}, {:cancel}), do: {:error, :already_cancelled}

  defp validate_command(_state, {:cancel}) do
    {:ok, [%{type: :subscription_cancelled}]}
  end

  # Reactivate
  defp validate_command(%{status: :cancelled}, {:reactivate}) do
    {:ok, [%{type: :subscription_reactivated}]}
  end

  defp validate_command(_state, {:reactivate}), do: {:error, :not_cancelled}