## Public schema, common Library (PubLib)

PubLib functions here are a subset of the PubLib-central Version 1 at<br/>&nbsp; http://git.addressforall.org/pg_pubLib-v1
<br/>Each project selects the functions it needs, maintaining it updated to be compatible with newer ones, of other projects, in the same database.

PubLib is an effort to reduce the impact of the "historic rationale" used by PostgreSQL developer team, like [the lack of overloads in some native functions, as the *round*() function](https://stackoverflow.com/a/20934099/287948), or the lack of [orthogonality](https://en.wikipedia.org/wiki/Orthogonal_instruction_set) in overloads and casts. PubLib is also a [Library of Snippets](https://wiki.postgresql.org/wiki/Category:Library_Snippets), implementating small and frequently used functions. Typical  "small function" are also [IMMUTABLE](https://www.postgresql.org/docs/current/xfunc-volatility.html) ones.

## Lib Organization

Functions are grouped in thematic source-files to maintainability. Most of the thematic groups comes from PostgreSQL Documentation's "[Chapter 9. Functions and Operators](https://www.postgresql.org/docs/current/functions.html)". Others are inspired in "snippet classes".  

Function group         | Labels | Inspiration
-----------------------|--------------|------------
(System) Administration  |  `admin`     |  [pg/docs/functions-admin](https://www.postgresql.org/docs/current/functions-admin.html)
Aggregate  |  `agg`/`aggregate`     |  [pg/docs/functions-aggregate](https://www.postgresql.org/docs/current/functions-aggregate.html)
GeoJSON  |  `geoJSON`     |  [PostGIS/GeoJSON](https://postgis.net/docs/ST_GeomFromGeoJSON.html)
JSON  |  `json`/`jsonb`     |  [pg/docs/functions-json](https://www.postgresql.org/docs/current/functions-admin.html)
PostGIS  |  `st`/`postGis`     |  [PostGIS/docs](https://postgis.net/docs/reference.html)
String  |  `str`/`string`     |  [pg/docs/functions-string](https://www.postgresql.org/docs/current/functions-string.html)

## Installation

Edit makefile of your project to run each `psql $(pg_uri)/$(pg_db) < pubLib$(i).sql` in the correct order. For example any `pubLib02-*.sql` must run before `pubLib03-*.sql`, but same tab-order like `pubLib03-admin.sql` and `pubLib03-json.sql` can be run in any order &mdash; by convention we adopt the alphabetic order, so use the `ls pubLib*.sql` order.
