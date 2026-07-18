  test "start_link without a :name option registers under the module name" do
    assert is_pid(Process.whereis(GraceWatchdog))
  end