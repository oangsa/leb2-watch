# LEB2 Watch

LEB2 Watch keeps a local projection of LEB2 assignment snapshots and describes
their freshness without claiming semantics the backend does not provide.

## Language

**Current assignment**:
An assignment present in the latest validated snapshot saved for the active
semester.
_Avoid_: Active assignment, live assignment

**Seen-only assignment**:
An assignment identity retained in the local observation ledger but absent
from the latest validated current snapshot.
_Avoid_: Deleted assignment, completed assignment

**Upcoming**:
A current assignment whose saved deadline exists and was not reported as
exceeded by the backend.
_Avoid_: Future assignment, due soon

**Overdue**:
A current assignment whose saved deadline exists and was reported as exceeded
by the backend.
_Avoid_: Late assignment, client-expired assignment

**Post-baseline discovery**:
A current assignment first observed after the semester's initial successful
snapshot. It is durable discovery evidence, not unread state or a publication
timestamp.
_Avoid_: Unread assignment, newly published assignment

**Stale cache**:
Saved assignment data whose latest retained terminal refresh did not succeed,
or whose successful refresh evidence is no longer retained.
_Avoid_: Old data

**Last-offline-failure**:
A latest refresh failure categorized as network unavailable. It describes the
last attempt, not the device's current connectivity.
_Avoid_: Offline

**Local notification target**:
A strictly validated assignment detail identity emitted after a user selects a
local notification. It is not an arbitrary route or display payload.
_Avoid_: Notification deep link, raw route

**Notification owner**:
The assignment-scoped effect identity that combines notification kind and,
for a deadline reminder, its positive offset.
_Avoid_: Notification payload, notification row

**Notification ID candidate**:
A deterministic positive int32 proposed for one Notification owner and probe.
It is not collision-free until later orchestration resolves it against durable
owner evidence.
_Avoid_: Collision-free notification ID, notification allocation

**Local notification claim**:
A durable assignment-scoped record that the app consumed a muted discovery or
committed to one app-level show request. It is not evidence of platform I/O,
OS display, delivery, acknowledgement, or read state.
_Avoid_: Delivered notification, notification receipt
