# Contraption — a BEAM-native automation platform

**Status:** concept, drafted 2026-07-12. Conference target: 2027 (talk + launch). Owner: Kip.

Contraption is an event-driven automation platform — the IFTTT/Zapier/Node-RED category — built as the BEAM-native product that category has never had. Workflows are supervised process graphs; triggers feed Broadway pipelines; durability comes from Oban; the builder is LiveView; edge deployment is Nerves. The differentiators over a generic clone: media pipelines as first-class steps (Membrane, Image), localization-native output (every human-facing message is MessageFormat 2 through Localize), real-world automation reach (home and industrial scenarios, cloud-to-edge), and a plugin standard the community can build on.

The name: a contraption is what the Mousetrap board game builds — and what the conference audience will build together, live.

## Why the BEAM is structurally correct for this category

* A workflow instance is a long-lived stateful reactor to events: a process (or `gen_statem`), supervised, isolated. Zapier/n8n/Temporal build this machinery; OTP ships it.

* Event ingest with backpressure is Broadway/GenStage. Durable retries, scheduling and uniqueness are Oban. The visual builder and live-run visualization are LiveView. Cloud-to-edge is distribution + Nerves. Every product layer maps to a hardened BEAM primitive.

* Per-workflow fault isolation is the category's hardest operational problem (one user's broken webhook must not touch another's pipeline) and the BEAM's founding feature.

* Nearest ecosystem prior art is Reactor (Ash ecosystem): an excellent saga/DAG execution engine, but an engine — no trigger/connector ecosystem, no builder, no multi-tenant runtime, no product. Evaluate building the execution layer *on* Reactor before writing a new one; either way the product layer is green field on the BEAM.

## Vocabulary

Five behaviours. The design rule: behaviours are the community-extensible surface, kept few and composable; routing and state are kernel concepts, not plugins.

* **Trigger** — a push event source. Webhook, cron/schedule, MQTT topic, RSS poll, sensor threshold crossing, file/upload arrival. Emits events into a workflow's Broadway pipeline.

* **Query** — an on-demand state read, used by conditions and transforms. Current temperature, presence, device state, an HTTP GET, a database lookup. The pull counterpart to Trigger's push (IFTTT added exactly this distinction for good reason: "when motion (trigger) and it is dark (query)").

* **Condition** — a boolean over the event plus queried state. Conditions gate edges and drive branching. Composable with and/or/not. Examples: threshold with hysteresis, schedule window, presence, rate limit, "value changed by more than X%".

* **Transform** — data in, data out, no external side effects. Image operations (Image), media pipeline stages (Membrane as the heavy transform), text/MF2 rendering, unit conversion (Localize units: the sensor reports °C, the user sees °F because their locale says so), extraction/mapping/aggregation.

* **Action** — a side effect. Actuate a device (MQTT publish, GPIO via Nerves, Home Assistant service call), notify (email/SMS/push/webhook — bodies are MF2 messages rendered in the recipient's locale), publish media, write records.

### Kernel concepts (not behaviours)

* **Branching.** Workflows are DAGs with conditional edges. A **switch** node routes an event down the first matching (or all matching) condition edges; explicit **if/else**; **split** fans an event to parallel paths; **join** merges with `:all | :any | {:quorum, n}` semantics and a timeout path. Every node has an optional **error edge** — failures route like data (saga-style compensation on the error path), which is what industrial scenarios demand: the failure path is part of the design, not an exception.

* **State.** Per-workflow persistent key-value state (setpoints, counters, last-seen values, debounce/hysteresis memory). Backed by the workflow process with periodic persistence; survives restarts via Oban-checkpointed snapshots.

* **Instances and identity.** A workflow definition is data (storable, versionable, renderable in the builder); an instance is a supervised process tree. Multi-tenant by construction.

## Real-world automation scenarios (design targets)

These four scenarios are the acceptance tests for the vocabulary — if they express cleanly, the design is right.

1. **Home: lighting.** Trigger: motion (MQTT/Zigbee). Conditions: lux below threshold (Query), within schedule window, someone home (Query: presence). Action: lights on; State: debounce timer; else-branch after timeout: lights off. Notification (if enabled) rendered per household member's locale.

2. **Home: heating with hysteresis.** Trigger: temperature reading. State: setpoint + hysteresis band. Condition: outside band. Action: actuate valve/relay. Transform: readings unit-localized for display.

3. **Industrial: line monitoring.** Trigger: vibration/temperature sensor stream (MQTT). Condition: threshold with rate-of-change. Split: (a) Action: throttle line via OPC-UA/Modbus write; (b) Transform: render alert with unit-localized readings → Action: notify on-call in their locale; (c) Action: append to audit log. Error edge on the actuation: escalate + fall back to notify-only.

4. **Industrial: visual QA.** Trigger: camera frame on part-passed (webhook/stream). Transform: Image-based defect check (or model call). Switch: pass → count; fail → Action: divert actuator + captured frame attached to the notification.

**Safety boundary — state it plainly and early.** Contraption is soft-real-time orchestration. It is not a safety PLC and never sits in a hard-real-time or safety-instrumented loop; interlocks and e-stops stay in hardware/PLC. Contraption supervises, orchestrates, records and notifies above that layer. Saying this loudly is what makes the industrial story credible rather than naive.

## Edge story (Nerves)

A Nerves gateway runs the same workflow runtime at the edge: local triggers/actions execute with LAN latency and survive WAN outage; definitions sync from the cloud node when connected. This is the BEAM distribution story made tangible — the same workflow definition, executing where the wires are. For the home scenarios it is also simply how people expect automation to behave (the lights must not depend on the internet).

## Connector shortlist (capped — the community builds the rest)

Reference implementations proving each behaviour, no more: webhook (in/out), cron, MQTT (trigger/query/action — covers most of home/industrial), Home Assistant, RSS, IMAP/SMTP or a push service, Image transform, Membrane pipeline transform, MF2 notify, HTTP query/action, Nerves GPIO, and `localize_emoji` search (the cameo). OAuth-heavy SaaS connectors are explicitly out of scope for v1 — that is Zapier's moat and the plugin standard's job.

## The conference demo — "the room builds a contraption"

**Mechanic.** The server generates a room-sized DAG with empty slots arranged in visible stages. Each phone that joins (QR code, LiveView) claims a slot and chooses one of three offered operations for it — choice creates ownership; the constrained menu keeps the machine coherent. The big screen shows the graph assembling as the room fills.

**The run.** A photo taken on stage enters stage one. The event cascades: each phone buzzes and lights when its step fires; the screen animates the token through the graph; transformations accumulate visibly (filters, captions in each phone-owner's locale, unit conversions). The cascade is **deliberately throttled** — Mousetrap machines delight because you can follow them.

**The OTP moment.** "Now — everyone in row twelve, turn off your phone." The supervisor reroutes around the dead steps live, the machine heals, the token keeps moving. Audience-initiated chaos engineering; the best supervision-tree demo it is possible to give.

**The physical closer.** The final Action is a Nerves device on stage: the last edge of the DAG fires a GPIO and something *physical* happens — a real marble drop, a flag, confetti. The room's phones built a contraption that ends in the world, which is the product's whole thesis in one image.

**The artifact.** A Membrane pipeline assembles the run — every transformation, every step-owner's locale — into a shareable video. The machine's output is the takeaway.

**Failure planning.** Conference wifi is the classic assassin: bring a dedicated AP; build a simulated-crowd mode so the full demo runs with zero connectivity; record a backup run. Audience inputs are menu choices only — no free text or uploads from the crowd.

## What this leverages (the "everything we built" ledger)

Localize (MF2 notifications, unit localization, per-user locale negotiation, list/date/number formatting in every rendered message), Image and the text tooling (transforms), Membrane (media pipelines and the artifact), Nerves (edge + the physical closer), Oban/Broadway/LiveView (the runtime), the Claude Code skill pattern (a Contraption skill for writing connectors, eventually).

## Timeline sketch

* **October 2026** — CLDR 49 cycle (already scheduled) ships the annotations pipeline; no Contraption work yet.
* **November–December 2026** — kernel spike: DAG + conditional edges + join/error semantics; Reactor build-vs-buy decision; Trigger/Query/Condition/Transform/Action behaviours; MQTT + webhook + cron connectors; scenario 1 running end-to-end headless.
* **January–February 2027** — LiveView builder + run visualization; Oban durability; State; scenarios 2–3; Nerves gateway spike.
* **March–April 2027** — demo mode (slot DAG, phone client, throttled cascade, simulated crowd), media connectors, the artifact pipeline, physical closer hardware.
* **May 2027 onward** — hardening, capacity test with simulated phones, talk outline, backup recording. Public repo + hex release timed to the conference.

## Open questions

* Build the execution layer on Reactor or write a purpose-built kernel? (Spike both in November; the deciding factors are conditional-edge ergonomics and per-instance supervision shape.)
* Definition format: data structure with a DSL on top — how much DSL for v1?
* Multi-tenancy depth for v1: single-node namespaces vs real isolation.
* Where does Contraption live — new org/repo, or under elixir-localize? (New repo; it is not a localization library, it is a consumer of them.)
* Licensing and hosted-vs-self-hosted posture — decide before the conference announcement.
