Write me an Elixir GenServer module called `PriorityEventBus` that implements an in-process pub/sub event system where subscribers receive events in **priority order**, and high-priority subscribers can **veto** delivery to lower-priority ones.

The motivation: plain pub/sub fans out every event to every subscriber concurrently, with no ordering between handlers. In some designs you want layered handling: a validator that runs first and can block subsequent processing; an audit logger that must observe an event before user-visible handlers get it; a cache invalidator that runs before the cache-consumer. This module adds priority ordering and a cancellation channel for these layered designs.

I need these functions in the public API:

- `PriorityEventBus.start_link(opts)` to start the process. It should accept a `:name` option for process registration. It should also accept a `:delivery_timeout_ms` option (default `5_000`) — the maximum time the bus will wait for a single subscriber's ack before moving on (see below).

- `PriorityEventBus.subscribe(server, topic, pid, priority)` subscribes `pid` to the exact topic string. `priority` is an integer — higher values run earlier. The bus must `Process.monitor` the subscriber. Returns `{:ok, ref}` where `ref` is the monitor reference and serves as the subscription identifier.

- `PriorityEventBus.unsubscribe(server, topic, ref)` removes the subscription. Demonitor the process if this was its last subscription. Returns `:ok`.

- `PriorityEventBus.publish(server, topic, event)` — this is where the semantics diverge from standard pub/sub. For each subscriber matching the topic (**exact match only — no wildcards**), in descending priority order:
  1. Send `{:event, topic, event, reply_to}` to the subscriber, where `reply_to` is `{pid_of_bus, unique_ref}`.
  2. Block waiting for the subscriber to reply with either `{:ack, unique_ref}` (continue delivery) or `{:cancel, unique_ref}` (stop delivery to all remaining lower-priority subscribers).
  3. If no reply arrives within `delivery_timeout_ms`, treat it as `:ack` (don't cancel downstream) and move on.
  4. Ties within the same priority level are delivered **in subscription order** (oldest subscription first), still respecting ack/cancel semantics.

  Returns `{:ok, delivered_count}` where `delivered_count` is the number of subscribers that actually received the event (those skipped due to a cancellation are not counted).

- `PriorityEventBus.ack(reply_to)` — convenience helper that a subscriber can call from its handler. `reply_to` is the `{bus_pid, unique_ref}` tuple the subscriber received. Sends `{:ack, unique_ref}` to `bus_pid`. Returns `:ok`.

- `PriorityEventBus.cancel(reply_to)` — like `ack/1` but sends `{:cancel, unique_ref}`. Used by high-priority handlers to veto delivery to lower-priority ones. Returns `:ok`.

- `PriorityEventBus.subscribers(server, topic)` — returns a list of `{ref, pid, priority}` tuples for all subscribers of a topic, sorted by descending priority then by subscription order within a priority level. Returns `[]` if no subscribers.

Ordering details to be precise about:

- Within a publish, subscribers are processed strictly serially (one at a time, awaiting each ack/cancel before starting the next). This is the opposite of standard fan-out pub/sub.
- Because publish blocks the GenServer on each subscriber's reply, any other call to the bus is queued behind an in-flight publish. This is intentional — it's the price of deterministic priority ordering.
- A subscriber's handler must run in the subscriber's own process (not inside the bus), so the bus uses `send/2` + a receive inside the publish handler, NOT `GenServer.call` on the subscriber.

When a monitored subscriber process goes down (`:DOWN` message), remove all its subscriptions across all topics. If an in-flight publish is waiting on a now-dead subscriber, treat it as `:ack` (continue, don't cancel) and continue delivery.

A single pid may subscribe to the same topic multiple times at different (or the same) priorities and will receive the event once per subscription, each time with its own `reply_to` ref. Each subscription is independently unsubscribable.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.