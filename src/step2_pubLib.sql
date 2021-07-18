/**
 * System's Public library (commom for WS and others)
 * PREFIXES: geojson_
 * Extra: PostGIS's Brazilian SRID inserts.
 * See also https://github.com/ppKrauss/SizedBigInt/blob/master/src_sql/step2-sizedNaturals.sql
 *          https://github.com/AddressForAll/WS/blob/master/src/sys_pubLib.sql
 */

CREATE extension IF NOT EXISTS postgis;

-------------------------------
-- system -generic

CREATE or replace FUNCTION pg_relation_lines(p_tablename text)
RETURNS bigint LANGUAGE 'plpgsql' AS $f$
  DECLARE
    lines bigint;
  BEGIN
      EXECUTE 'SELECT COUNT(*) FROM '|| $1 INTO lines;
      RETURN lines;
  END
$f$;
COMMENT ON FUNCTION pg_relation_lines
  IS 'run COUNT(*), a complement for pg_relation_size() function.'
;

CREATE or replace FUNCTION  jsonb_objslice(
    key text, j jsonb, rename text default null
) RETURNS jsonb AS $f$
    SELECT COALESCE( jsonb_build_object( COALESCE(rename,key) , j->key ), '{}'::jsonb )
$f$ LANGUAGE SQL IMMUTABLE;  -- complement is f(key text[], j jsonb, rename text[])
COMMENT ON FUNCTION jsonb_objslice(text,jsonb,text)
  IS 'Get the key as encapsulated object, with same or changing name.'
;

-- GeoJSON complements:

CREATE or replace FUNCTION geojson_readfile_headers(
    f text,   -- absolute path and filename
    missing_ok boolean DEFAULT false -- an error is raised, else (if true), the function returns NULL when file not found.
) RETURNS JSONb AS $f$
  SELECT j || jsonb_build_object( 'file',f,  'content_header', pg_read_file(f)::JSONB - 'features' )
  FROM to_jsonb( pg_stat_file(f,missing_ok) ) t(j)
  WHERE j IS NOT NULL
$f$ LANGUAGE SQL;


CREATE or replace FUNCTION geojson_readfile_features_jgeom(file text, file_id int default null) RETURNS TABLE (
  file_id int, feature_id int, feature_type text, properties jsonb, jgeom jsonb
) AS $f$
   SELECT file_id, (ROW_NUMBER() OVER())::int AS subfeature_id,
          subfeature->>'type' AS subfeature_type,
          subfeature->'properties' AS properties,
          crs || subfeature->'geometry' AS jgeom
   FROM (
      SELECT j->>'type' AS geojson_type,
             jsonb_objslice('crs',j) AS crs,
             jsonb_array_elements(j->'features') AS subfeature
      FROM ( SELECT pg_read_file(file)::JSONb AS j ) jfile
   ) t2
$f$ LANGUAGE SQL;
COMMENT ON FUNCTION geojson_readfile_features_jgeom(text,int)
  IS 'Reads a big GeoJSON file and transforms it into a table with a json-geometry column.'
;

-- drop  FUNCTION geojson_readfile_features;
CREATE or replace FUNCTION geojson_readfile_features(f text) RETURNS TABLE (
  fname text, feature_id int, geojson_type text,
  feature_type text, properties jsonb, geom geometry
) AS $f$
   SELECT fname, (ROW_NUMBER() OVER())::int, -- feature_id,
          geojson_type, feature->>'type',    -- feature_type,
          jsonb_objslice('name',feature) || feature->'properties', -- properties and name.
          -- see CRS problems at https://gis.stackexchange.com/questions/60928/
          ST_GeomFromGeoJSON(  crs || (feature->'geometry')  ) AS geom
   FROM (
      SELECT j->>'file' AS fname,
             jsonb_objslice('crs',j) AS crs,
             j->>'type' AS geojson_type,
             jsonb_array_elements(j->'features') AS feature
      FROM ( SELECT pg_read_file(f)::JSONb AS j ) jfile
   ) t2
$f$ LANGUAGE SQL;
COMMENT ON FUNCTION geojson_readfile_features(text)
  IS 'Reads a small GeoJSON file and transforms it into a table with a geometry column.'
;

CREATE or replace FUNCTION ST_AsGeoJSONb( -- ST_AsGeoJSON_complete
  -- st_asgeojsonb(geometry, integer, integer, bigint, jsonb
  p_geom geometry,
  p_decimals int default 6,
  p_options int default 1,  -- 1=better (implicit WGS84) tham 5 (explicit)
  p_id text default null,
  p_properties jsonb default null,
  p_name text default null,
  p_title text default null,
  p_id_as_int boolean default false
) RETURNS JSONb AS $f$
-- Do ST_AsGeoJSON() adding id, crs, properties, name and title
  SELECT ST_AsGeoJSON(p_geom,p_decimals,p_options)::jsonb
       || CASE
          WHEN p_properties IS NULL OR jsonb_typeof(p_properties)!='object' THEN '{}'::jsonb
          ELSE jsonb_build_object('properties',p_properties)
          END
       || CASE
          WHEN p_id IS NULL THEN '{}'::jsonb
          WHEN p_id_as_int THEN jsonb_build_object('id',p_id::bigint)
          ELSE jsonb_build_object('id',p_id)
          END
       || CASE WHEN p_name IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('name',p_name) END
       || CASE WHEN p_title IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('title',p_title) END
$f$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION ST_AsGeoJSONb IS $$
  Enhances ST_AsGeoJSON() PostGIS function.
  Use ST_AsGeoJSONb( geom, 6, 1, osm_id::text, stable.element_properties(osm_id) - 'name:' ).
$$;

-------------------------------

-- IBGE Albers, SRID number convention in Project DigitalGuard-BR:
INSERT into spatial_ref_sys (srid, auth_name, auth_srid, proj4text, srtext)
VALUES (
  952019,
  'BR:IBGE',
  52019,
  '+proj=aea +lat_0=-12 +lon_0=-54 +lat_1=-2 +lat_2=-22 +x_0=5000000 +y_0=10000000 +ellps=WGS84 +units=m +no_defs',
  $$PROJCS[
  "Conica_Equivalente_de_Albers_Brasil",
  GEOGCS[
    "GCS_SIRGAS2000",
    DATUM["D_SIRGAS2000",SPHEROID["Geodetic_Reference_System_of_1980",6378137,298.2572221009113]],
    PRIMEM["Greenwich",0],
    UNIT["Degree",0.017453292519943295]
  ],
  PROJECTION["Albers"],
  PARAMETER["standard_parallel_1",-2],
  PARAMETER["standard_parallel_2",-22],
  PARAMETER["latitude_of_origin",-12],
  PARAMETER["central_meridian",-54],
  PARAMETER["false_easting",5000000],
  PARAMETER["false_northing",10000000],
  UNIT["Meter",1]
 ]$$
)
ON CONFLICT DO NOTHING;
