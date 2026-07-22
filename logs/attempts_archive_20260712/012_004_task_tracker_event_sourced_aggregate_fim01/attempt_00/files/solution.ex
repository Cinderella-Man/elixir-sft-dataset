  defp apply_event(%{type: :task_created, title: title, priority: priority}, _nil_state) do
    %{title: title, assignee: nil, status: :created, priority: priority}
  end

  defp apply_event(%{type: :task_assigned, assignee: assignee}, state) do
    %{state | assignee: assignee}
  end

  defp apply_event(%{type: :task_started}, state) do
    %{state | status: :in_progress}
  end

  defp apply_event(%{type: :task_completed}, state) do
    %{state | status: :completed}
  end

  defp apply_event(%{type: :task_reopened}, state) do
    %{state | status: :created, assignee: nil}
  end