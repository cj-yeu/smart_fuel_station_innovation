# Nearby OpenStreetMap fuel-station evidence

## Source and attribution

Nearby fuel-station evidence is sourced from **OpenStreetMap contributors**.
The returned attribution must remain visible and link to the official
[OpenStreetMap copyright and licence page](https://www.openstreetmap.org/copyright).
OpenStreetMap data is available under the [Open Database License (ODbL)](https://opendatacommons.org/licenses/odbl/).

The server-controlled Overpass query uses only the established OSM tag
`amenity=fuel`. It requests nodes, ways, and relations, with centres for ways
and relations. A returned `fetched_at` value identifies when cached evidence
was retrieved. Server requests identify **Smart Fuel Station Innovation** with
the repository contact URL
`https://github.com/cj-yeu/smart_fuel_station_innovation`.

## Operational limits

Overpass is a community service and can be unavailable, rate-limited, delayed,
or incomplete. Results are cached for 24 hours using the exact validated
latitude, longitude, and analysis radius as the cache identity; no coordinate
rounding is used. OSM completeness is not guaranteed. `station_count` is the
capped number of stations returned, not an upstream total. The private server
cache retains the bounded provider response and normalized result with fetched
and expiry timestamps; it is not exposed through normal API table access.

This evidence is decision-support data only. It is not authoritative proof of
fuel-station ownership, does not classify a station as own versus competitor,
and must never directly determine an assessment score. Own/competitor
classification requires a separate authoritative company station registry.
An Overpass failure returns no evidence and does not change assessment scoring.
