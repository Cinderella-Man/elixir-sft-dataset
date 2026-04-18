Write me an Elixir GenServer module called `EventBus` that implements an in-process pub/sub event system with wildcard topic support.

I need these functions in the public API:

- `EventBus.start_link(opts)` to start the process. It should accept a `:name` option for process registration.

- `EventBus.subscribe(server, topic, pid)` which subscribes the given pid to a topic. The EventBus must automatically `Process.monitor` the subscriber so dead processes get cleaned up. Return `{:ok, ref}` where `ref` is the monitor reference, which also serves as the subscription identifier.

- `EventBus.unsubscribe(server, topic, ref)` which removes the subscription identified by `ref` from the given topic. Demonitor the process when its last subscription is removed. Return `:ok`.

- `EventBus.publish(server, topic, event)` which sends `{:event, topic, event}` to every pid subscribed to a matching topic. A subscription matches if the subscribed topic is exactly equal to the published topic, OR if the subscribed topic is a wildcard pattern. Return `:ok`.

Wildcard matching rules: a `"*"` segment matches exactly one segment. Segments are separated by `"."`. For example, `"orders.*"` matches `"orders.created"` and `"orders.updated"` but not `"orders.items.created"` and not `"orders"`. The pattern `"*.*"` matches any two-segment topic. A literal topic like `"orders.created"` only matches exactly `"orders.created"`.

When a monitored subscriber process goes down (the GenServer receives a `:DOWN` message), automatically remove all of that process's subscriptions across all topics. If that was the last subscription being monitored for that process, no further cleanup is needed since the monitor fires only once.

A single pid may subscribe to the same topic multiple times and should receive the event once per subscription. Each subscription is independently unsubscribable via its own ref.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.