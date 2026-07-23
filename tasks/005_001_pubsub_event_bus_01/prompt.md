# EventBus: In-Process Pub/Sub Event System — Specification

## Overview

This document specifies an Elixir GenServer module named `EventBus` that implements an in-process publish/subscribe event system with wildcard topic support. The complete module is to be delivered in a single file. It must rely only on the OTP standard library, with no external dependencies.

## API

The module must expose the following public functions:

- `EventBus.start_link(opts)` starts the process. It accepts a `:name` option for process registration.

- `EventBus.subscribe(server, topic, pid)` subscribes the given pid to a topic. The EventBus must automatically `Process.monitor` the subscriber so that dead processes get cleaned up. It returns `{:ok, ref}`, where `ref` is the monitor reference, which also serves as the subscription identifier.

- `EventBus.unsubscribe(server, topic, ref)` removes the subscription identified by `ref` from the given topic. It demonitors the process when its last subscription is removed. It returns `:ok`.

- `EventBus.publish(server, topic, event)` sends `{:event, topic, event}` to every pid subscribed to a matching topic. A subscription matches if the subscribed topic is exactly equal to the published topic, OR if the subscribed topic is a wildcard pattern. It returns `:ok`.

## Wildcard Matching

Wildcard matching follows these rules. A `"*"` segment matches exactly one segment. Segments are separated by `"."`. For example, `"orders.*"` matches `"orders.created"` and `"orders.updated"` but does not match `"orders.items.created"` and does not match `"orders"`. The pattern `"*.*"` matches any two-segment topic. A literal topic such as `"orders.created"` only matches exactly `"orders.created"`.

## Edge cases

When a monitored subscriber process goes down (that is, when the GenServer receives a `:DOWN` message), all of that process's subscriptions across all topics must be automatically removed. If that was the last subscription being monitored for that process, no further cleanup is needed, since the monitor fires only once.

A single pid may subscribe to the same topic multiple times, and it should receive the event once per subscription. Each subscription is independently unsubscribable via its own ref.
