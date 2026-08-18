# East Malaysia boundary data

## Dataset and licence

The East Malaysia geographic validator uses an extracted subset of
**geoBoundaries MYS ADM1**, created by **geoBoundaries / William & Mary geoLab
and contributors**.

- Project: <https://www.geoboundaries.org/>
- Licence: [Creative Commons Attribution 4.0 International (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/)
- Approved local source: `geoboundaries_mys_adm1.geojson`
- Approved SHA-256: `de8b44337315de60019951d76744765ebdd5efc9c5823e0933b4dc15a0ed20d4`
- Original collection: 16 ADM1 features
- Original CRS: `urn:ogc:def:crs:OGC:1.3:CRS84`

Only these three unique source features are included:

| Territory | shapeISO | shapeID |
| --- | --- | --- |
| Sabah | `MY-12` | `15666254B50935235229272` |
| Sarawak | `MY-13` | `15666254B8535925993004` |
| Labuan | `MY-15` | `15666254B4265207353082` |

No other Malaysian state or source feature is included.

## Transformation and storage

The source geometries are full-resolution GeoJSON `MultiPolygon` objects.
OGC CRS84 coordinates use longitude/X followed by latitude/Y. The seed
migration parses each exact geometry with the schema-qualified PostGIS GeoJSON
parser and explicitly assigns SRID 4326 without swapping axes.

No simplification, buffering, bounding-box substitution, manual boundary edit,
coordinate inference, or automatic validity repair is performed. The migration
requires each source geometry to already be non-empty, valid, two-dimensional,
SRID 4326, and `MultiPolygon`. It also rejects any cross-territory area overlap
while allowing shared boundary lines or points.

The data is stored in:

- `public.east_malaysia_boundary_datasets` for dataset provenance and activation
- `public.east_malaysia_territory_boundaries` for the three territory geometries

The deterministic dataset UUID is
`de8b4433-7315-5e60-8195-1d76744765eb`. Its version field records the approved
source SHA-256 rather than inventing a release number. The dataset is activated
only after all three stored boundaries pass the migration validations.

## Validator use and attribution

`public.validate_east_malaysia_site(double precision, double precision,
smallint)` reads the single active, complete dataset. It derives company
authority from `profiles.company_id`; it does not trust Auth metadata or a
client-supplied territory. The application displays persistent attribution near
the map:

> Boundary validation: geoBoundaries (CC BY 4.0)

The geoBoundaries name links to <https://www.geoboundaries.org/> and the licence
label links to <https://creativecommons.org/licenses/by/4.0/>. Existing
OpenStreetMap tile attribution remains separate and unchanged.

## Updating or replacing the dataset

Any future update must be a separately reviewed forward migration. Before
replacement:

1. Obtain a source-specific individual-country ADM1 file and its licence
   metadata without silently substituting another provider.
2. Record and independently verify the exact source SHA-256, feature count, CRS,
   names, ISO codes, shape IDs, uniqueness, and geometry types.
3. Review the licence and visible attribution requirements.
4. Extract only Sabah, Sarawak, and Labuan without modifying their geometry.
5. Validate geometry structure, validity, SRID, territory completeness, and
   cross-territory area overlap in an isolated PostgreSQL/PostGIS environment.
6. Exercise the transactional SQL test and a rollback/recovery verification
   before considering Production deployment.
7. Never mutate an active dataset in place or bypass the owner-maintained table
   ACLs from application code.

## Notice

Use of this dataset does not imply endorsement by geoBoundaries, William & Mary,
or any Malaysian government body, and it does not give the data official
Malaysian government status. geoBoundaries provides the source without warranty;
the application must continue to fail closed when authoritative validation is
unavailable or ambiguous.
