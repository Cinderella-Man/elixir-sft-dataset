defp validate_command(nil, {:create, title, priority}) do
  if priority in @valid_priorities do
    {:ok, [%{type: :task_created, title: title, priority: priority}]}
  else
    {:error, :invalid_priority}
  end
end

defp validate_command(_state, {:create, _title, _priority}), do: {:error, :already_exists}

defp validate_command(nil, _command), do: {:error, :not_found}

defp validate_command(%{status: :completed}, {:assign, _assignee}),
  do: {:error, :already_completed}

defp validate_command(_state, {:assign, assignee}) do
  {:ok, [%{type: :task_assigned, assignee: assignee}]}
end

defp validate_command(%{assignee: nil}, {:start}), do: {:error, :not_assigned}
defp validate_command(%{status: :in_progress}, {:start}), do: {:error, :already_started}

defp validate_command(_state, {:start}) do
  {:ok, [%{type: :task_started}]}
end

defp validate_command(%{status: :in_progress}, {:complete}) do
  {:ok, [%{type: :task_completed}]}
end

defp validate_command(_state, {:complete}), do: {:error, :not_in_progress}

defp validate_command(%{status: :completed}, {:reopen}) do
  {:ok, [%{type: :task_reopened}]}
end

defp validate_command(_state, {:reopen}), do: {:error, :not_completed}