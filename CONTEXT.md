# LEB2 Watch

LEB2 Watch keeps a local projection of LEB2 assignment snapshots and describes
their freshness without claiming semantics the backend does not provide.

## Language

**Current assignment**:
An assignment present in the latest validated snapshot saved for the active
semester.
_Avoid_: Active assignment, live assignment

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
