/**
 * HOMOLOG - Testes sistemáticos ou amostrais para certificar que tudo bate com os shapefiles.
 **/

CREATE or replace FUNCTION grid_ibge.homolog_prepare(p_sample_percent real DEFAULT 0.01) RETURNS text AS $f$
DECLARE
   q text;
   qvw_sample text  :='grade_all_ids_sample';
   qvw_full text    :='grade_all_ids';
   is_first boolean := true;
BEGIN
 RAISE NOTICE ' Criando VIEWS % e %...', qvw_sample, qvw_full;
 q = 'DROP VIEW IF EXISTS %1$s CASCADE; CREATE VIEW %1$s AS';
 qvw_sample := format(q, qvw_sample);
 qvw_full   := format(q, qvw_full);
 FOREACH q IN ARRAY grid_ibge.quadrantes_text('grade_id')
 LOOP
    qvw_sample := qvw_sample || format(
      E'\n %s SELECT * FROM %s TABLESAMPLE BERNOULLI(%s)',
      CASE WHEN is_first THEN '' ELSE 'UNION ALL ' END,
      q, p_sample_percent
    );
    qvw_full := qvw_full || format(
      E'\n %s SELECT * FROM  %s',
      CASE WHEN is_first THEN '' ELSE 'UNION ALL ' END,
      q
    );
    is_first := false;
 END LOOP;
 EXECUTE qvw_sample;
 EXECUTE qvw_full;
 RETURN 'sucesso';
END;
$f$ LANGUAGE PLpgSQL;
COMMENT ON FUNCTION grid_ibge.homolog_prepare
  IS 'Prepara VIEWS para homologar grade compacta contra dados originais da Grade Estatística IBGE.';

SELECT grid_ibge.homolog_prepare();

CREATE or replace FUNCTION grade_all_ids_search_latlon(lat real, lon real) RETURNS TABLE (LIKE grade_id04) AS $f$
 SELECT g.*
 FROM  grade_all_ids g,
       ( SELECT ST_SetSRID( ST_MakePoint(lon,lat),4326) ) t(pt_geom)
 WHERE g.geom && t.pt_geom
$f$ LANGUAGE SQL IMMUTABLE;

CREATE or replace FUNCTION grade_all_ids_search_latlon(geouri text) RETURNS TABLE (LIKE grade_id04) AS $f$
 SELECT grade_all_ids_search_latlon(p[1]::real, p[2]::real)
 FROM ( SELECT regexp_match(geoURI,'^geo:([+\-]?\d+\.?\d*),([+\-]?\d+\.?\d*)(?:;.+)?$') ) t1(p)
$f$ LANGUAGE SQL IMMUTABLE;

DROP TABLE IF EXISTS grid_ibge.homolog_sample_pt;
CREATE TABLE grid_ibge.homolog_sample_pt (
  jurisdiction text,
  name text,
  geo_uri text PRIMARY KEY,
  wikidata_id bigint,
  osm_node_id bigint,
  ibge_cell_nome text
);
COPY grid_ibge.homolog_sample_pt FROM '/tmp/ptCtrl.csv' CSV HEADER;

DROP MATERIALIZED VIEW IF EXISTS grid_ibge.mvw_homolog_sample_pt;
CREATE MATERIALIZED VIEW grid_ibge.mvw_homolog_sample_pt AS
  SELECT t.*, s.*, ST_Centroid(t.geom) as pt_geom
  FROM grid_ibge.homolog_sample_pt s, LATERAL grade_all_ids_search_latlon(s.geo_uri) t
;
-- for QGIS, drop view grid_ibge.vw_original_ibge_rebuild;
/* to generate sample set!
COPY (
  SELECT jurisdiction, name, geo_uri, wikidata_id, osm_node_id, id_unico as  ibge_cell_nome
  FROM grid_ibge.mvw_homolog_sample_pt
) TO '/tmp/ptCtrl2.csv' CSV HEADER;
*/

-- Check names:
SELECT geo_uri, id_unico,
  id_unico=grid_ibge.gid_to_name(gid_new) AS is_unico,
  nome_1km=grid_ibge.xyLany_to_name(xyLany,5)  AS is_name1km,grid_ibge.xyLany_to_name(xyLany,5) as name1km,
  nome_1km
  ,nome_5km=grid_ibge.xyLany_to_name(xyLany,4)  AS is_name5km
  ,nome_10km=grid_ibge.xyLany_to_name(xyLany,3)  AS is_name10km
--  ,nome_50km=grid_ibge.xyLany_to_name(xyLany,2)  AS is_name50km
--  ,nome_100km=grid_ibge.xyLany_to_name(xyLany,1)  AS is_name100km
--  ,nome_500km=grid_ibge.xyLany_to_name(xyLany,0)  AS is_name500km
FROM (
  -- CUIDADO, JOIN funcionando só para pontos distantes mais de 1km ou 200m entre si.
  SELECT c.gid as gid_new, s.*, grid_ibge.gid_to_xyLref(c.gid) xyLany
  FROM grid_ibge.mvw_homolog_sample_pt s INNER JOIN grid_ibge.censo2010_info c
    ON c.gid = grid_ibge.name_to_gid(s.id_unico)
) t1;


-- LXIO Testa conversão direta da geoURI:
SELECT geo_uri,id_unico,
 CASE WHEN id_unico!=nome_1km THEN grid_ibge.gid_to_name(grid_ibge.geoURI_to_gid(geo_uri,6)) ELSE NULL END AS is_name200m,
 nome_1km = grid_ibge.gid_to_name(grid_ibge.geoURI_to_gid(geo_uri))  AS is_name1km,
 nome_5km = grid_ibge.gid_to_name(grid_ibge.geoURI_to_gid(geo_uri,4))  AS is_name5km,
 nome_10km = grid_ibge.gid_to_name(grid_ibge.geoURI_to_gid(geo_uri,3))  AS is_name10km,
 nome_50km = grid_ibge.gid_to_name(grid_ibge.geoURI_to_gid(geo_uri,2))  AS is_name50km,
 nome_100km = grid_ibge.gid_to_name(grid_ibge.geoURI_to_gid(geo_uri,1)) AS is_name100km,
 nome_500km = grid_ibge.gid_to_name(grid_ibge.geoURI_to_gid(geo_uri,0)) AS is_name500km
FROM (
 -- CUIDADO, JOIN funcionando só para pontos distantes mais de 1km entre si.
 SELECT c.gid as gid_new, s.*, grid_ibge.gid_to_xyLref(c.gid) xyL_1km
 FROM grid_ibge.mvw_homolog_sample_pt s INNER JOIN grid_ibge.censo2010_info c
   ON c.gid = grid_ibge.name_to_gid(s.nome_1km)
) t1;


-- Testa conversão direta da geoURI:
SELECT geo_uri,id_unico,gid_new,
 CASE WHEN id_unico!=nome_1km THEN grid_ibge.gid_to_name(grid_ibge.geoURI_to_gid(geo_uri,6)) ELSE NULL END AS is_name200m,
 nome_1km = grid_ibge.gid_to_name(grid_ibge.geoURI_to_gid(geo_uri))  AS is_name1km,
 nome_5km = grid_ibge.gid_to_name(grid_ibge.geoURI_to_gid(geo_uri,4))  AS is_name5km,
 nome_10km = grid_ibge.gid_to_name(grid_ibge.geoURI_to_gid(geo_uri,3))  AS is_name10km,
 nome_50km = grid_ibge.gid_to_name(grid_ibge.geoURI_to_gid(geo_uri,2))  AS is_name50km,
 nome_100km = grid_ibge.gid_to_name(grid_ibge.geoURI_to_gid(geo_uri,1)) AS is_name100km,
 nome_500km = grid_ibge.gid_to_name(grid_ibge.geoURI_to_gid(geo_uri,0)) AS is_name500km
FROM (
 -- CUIDADO, JOIN funcionando só para pontos distantes mais de 1km ou 200m entre si.
 SELECT c.gid as gid_new, s.*, grid_ibge.gid_to_xyLref(c.gid) xyL_1km
 FROM grid_ibge.mvw_homolog_sample_pt s INNER JOIN grid_ibge.censo2010_info c
   ON c.gid = grid_ibge.name_to_gid(s.id_unico)
) t1;



-- -- -- -- -- -- -- -- -- -- -- -- --
-- -- MAIS TESTES POR CONVERSÃO DE NOME:

SELECT n_samples*3 = n_cmps AS all_samples_ok
FROM (
  SELECT SUM(is_name1km::int + is_name5km::int + is_name100km::int) as n_cmps, count(*) n_samples
  FROM (
    SELECT nome_1km = grid_ibge.gid_to_name(grid_ibge.name_to_gid(nome_1km)) AS is_name1km,
           nome_5km = grid_ibge.gid_to_name(grid_ibge.name_to_gid(nome_5km)) AS is_name5km,
           nome_100km = grid_ibge.gid_to_name(grid_ibge.name_to_gid(nome_100km)) AS is_name100km
    FROM grade_all_ids_sample
  ) t1
) t2;

-- -- -- -- -- -- -- -- -- -- -- -- --
-- -- MAIS TESTES POR CONVERSÃO DE GEOMETRIA:
/*
  SELECT SUM(is_name1km::int + is_name5km::int + is_name100km::int) as n_cmps, count(*) n_samples
  FROM (
    st_centroid ( )  ver ptgeom
    SELECT nome_1km = grid_ibge.gid_to_name(grid_ibge.name_to_gid(nome_1km)) AS is_name1km,
           nome_5km = grid_ibge.gid_to_name(grid_ibge.name_to_gid(nome_5km)) AS is_name5km,
           nome_100km = grid_ibge.gid_to_name(grid_ibge.name_to_gid(nome_100km)) AS is_name100km
    FROM grade_all_ids_sample
  ) t1
*/

-- TESTAR GEOMETRIAS: ...

------------------------------------------------------------------------------------
-- BUSCAS E SEU PREPARO, Brute forte search:


CREATE MATERIALIZED VIEW grid_ibge.mvw_censo2010_info_XbfSearch AS
  SELECT DISTINCT xyL[3]::smallint as level, xyL[1] AS x
  FROM (
    SELECT grid_ibge.gid_to_xyLcenter(gid) AS xyL FROM grid_ibge.censo2010_info
  ) t
;
CREATE INDEX mvw_censo2010_info_XbfSearch_xbtree ON grid_ibge.mvw_censo2010_info_XbfSearch(level,x);

CREATE MATERIALIZED VIEW grid_ibge.mvw_censo2010_info_YbfSearch AS
  SELECT DISTINCT xyL[3]::smallint as level, xyL[2] AS y
  FROM (
    SELECT grid_ibge.gid_to_xyLcenter(gid) AS xyL FROM grid_ibge.censo2010_info
  ) t
;
CREATE INDEX mvw_censo2010_info_YbfSearch_ybtree ON grid_ibge.mvw_censo2010_info_YbfSearch(level,y);

-----
CREATE FUNCTION grid_ibge.bfsearch_xyL(p_x int, p_y int, p_level smallint) RETURNS int[] AS $f$
   -- a busca parte da presunção de existência, ou seja, ponto dentro da grade.
   SELECT array[t1x.x, t1y.y, p_level::int]
   FROM (
    SELECT x FROM (
      (
        SELECT x
        FROM grid_ibge.mvw_censo2010_info_XbfSearch
        WHERE level=p_level AND x >= p_x
        ORDER BY x LIMIT 1
      )  UNION ALL (
        SELECT x
        FROM grid_ibge.mvw_censo2010_info_XbfSearch
        WHERE level=p_level AND x < p_x
        ORDER BY x DESC LIMIT 1
      )
    ) t0x
    ORDER BY abs(p_x-x) LIMIT 1
  ) t1x, (
    SELECT y FROM (
      (
        SELECT y
        FROM grid_ibge.mvw_censo2010_info_YbfSearch
        WHERE level=p_level AND y >= p_y
        ORDER BY y LIMIT 1
      )  UNION ALL (
        SELECT y
        FROM grid_ibge.mvw_censo2010_info_YbfSearch
        WHERE level=p_level AND y < p_y
        ORDER BY y DESC LIMIT 1
      )
    ) t0y
    ORDER BY abs(p_y-y)
    LIMIT 1
  ) t1y
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION grid_ibge.bfsearch_xyL_bylatlon(
  lat real, lon real, p_level int
) RETURNS int[] AS $f$
  SELECT grid_ibge.bfsearch_xyL(ST_X(geom)::int, ST_Y(geom)::int, p_level::smallint)
  FROM (SELECT ST_Transform( ST_SetSRID( ST_MakePoint(lon,lat),4326), 952019 )) t(geom);
$f$ LANGUAGE SQL IMMUTABLE;
-- select grid_ibge.bfsearch_xyL_bylatlon(-23.550278::real,-46.633889::real,6::smallint);

CREATE FUNCTION grid_ibge.bfsearch_xyL(geoURI text, p_level int DEFAULT 5) RETURNS int[] AS $wrap$
  SELECT grid_ibge.bfsearch_xyL_bylatlon( p[1]::real, p[2]::real, p_level )
  FROM ( SELECT regexp_match(geoURI,'^geo:([+\-]?\d+\.?\d*),([+\-]?\d+\.?\d*)(?:;.+)?$') ) t(p);
$wrap$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION grid_ibge.bfsearch_to_gid(p_x int, p_y int, p_level smallint) RETURNS bigint AS $f$
  SELECT grid_ibge.xylcenter_to_gid(p[1], p[2], p_level)
  FROM ( SELECT grid_ibge.bfsearch_xyL(p_x, p_y, p_level) ) t(p)
$f$ LANGUAGE SQL IMMUTABLE;


-- CREATE FUNCTION grid_ibge.gid_contains(gid bigint, gid_into bigint) RETURNS bigint
-- drop FUNCTION grid_ibge.bfsearch_cell;
CREATE FUNCTION grid_ibge.bfsearch_cell(p_x real, p_y real, p_level smallint) RETURNS bigint AS $wrap$
  SELECT grid_ibge.bfsearch_to_gid( round(p_x)::int, round(p_y)::int, p_level );
$wrap$ LANGUAGE SQL IMMUTABLE;
-- precisa? grid_ibge.bfsearch_snapcell para arredondar conforme o nível.

--DROP grid_ibge.bfsearch_cell_bylatlon;
CREATE FUNCTION grid_ibge.bfsearch_cell_bylatlon(
  lat real, lon real, p_level int
) RETURNS bigint AS $f$
  SELECT grid_ibge.bfsearch_cell(ST_X(geom)::real, ST_Y(geom)::real, p_level::smallint)
  FROM (SELECT ST_Transform( ST_SetSRID( ST_MakePoint(lon,lat),4326), 952019 )) t(geom);
$f$ LANGUAGE SQL IMMUTABLE;
-- select grid_ibge.bfsearch_cell_bylatlon(-23.550278::real,-46.633889::real,6::smallint);

CREATE FUNCTION grid_ibge.bfsearch_cell(geoURI text, p_level int DEFAULT 5) RETURNS bigint AS $wrap$
  SELECT grid_ibge.bfsearch_cell_bylatlon( p[1]::real, p[2]::real, p_level )
  FROM ( SELECT regexp_match(geoURI,'^geo:([+\-]?\d+\.?\d*),([+\-]?\d+\.?\d*)(?:;.+)?$') ) t(p);
  -- exemplo de opções para split(';')  'crs=BR_ALBERS_IBGE;u=200'
  -- FALTA snap Uncertainty to level
$wrap$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION grid_ibge.bfsearch_cell_bylatlon(lat numeric, lon numeric, p_level int) RETURNS bigint AS $wrap$
  SELECT grid_ibge.bfsearch_cell_bylatlon(lat::real,lon::real,p_level)
$wrap$ LANGUAGE SQL IMMUTABLE;
CREATE FUNCTION grid_ibge.bfsearch_cell_bylatlon(lat float, lon float, p_level int) RETURNS bigint AS $wrap$
  SELECT grid_ibge.bfsearch_cell_bylatlon(lat::real,lon::real,p_level)
$wrap$ LANGUAGE SQL IMMUTABLE;
-- select grid_ibge.bfsearch_cell_bylatlon(-23.550278,-46.633889,6);


/*
-- REFRESHES DO "BRUTE FORCE SEARCH":
REFRESH MATERIALIZED VIEW  grid_ibge.mvw_censo2010_info_XbfSearch;  -- pode levar horas!
REFRESH MATERIALIZED VIEW  grid_ibge.mvw_censo2010_info_YbfSearch;  -- pode levar horas!

SELECT min(x) x_min, max(x) x_max FROM grid_ibge.mvw_censo2010_info_XbfSearch;
SELECT min(y) y_min, max(y) y_max FROM grid_ibge.mvw_censo2010_info_YbfSearch;

*/
