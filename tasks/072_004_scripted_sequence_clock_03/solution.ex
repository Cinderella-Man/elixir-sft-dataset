@impl GenServer
def init({script, policy}) do
  cond do
    script == [] -> {:stop, :empty_script}
    not Enum.all?(script, &match?(%DateTime{}, &1)) -> {:stop, :invalid_script}
    policy not in @policies -> {:stop, :invalid_policy}
    true -> {:ok, %{script: script, index: 0, policy: policy}}
  end
end