  def release(server, bucket, lease_id, outcome) when outcome in [:completed, :cancelled] do
    GenServer.call(server, {:release, bucket, lease_id, outcome})
  end