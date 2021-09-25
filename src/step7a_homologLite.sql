/**
 * HOMOLOG - Testes sistemáticos ou amostrais para certificar que tudo bate com os shapefiles.
 * PARTE B - "fast", não demora muito.
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

CREATE or replace FUNCTION grid_ibge.drop_original() RETURNS text AS $f$
DECLARE
 tabname text;
 q       text  :='';
BEGIN
FOREACH tabname IN ARRAY grid_ibge.quadrantes_text('grade_id')
LOOP
  q := q || format(E'\nDROP TABLE IF EXISTS %1$s CASCADE;', tabname);
END LOOP;
EXECUTE q;
RETURN 'tabelas IBGE originais removidas';
END;
$f$ LANGUAGE PLpgSQL;


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

DROP TABLE IF EXISTS grid_ibge.homolog_sample_pt CASCADE;
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

-- Check names:   FALHA talvez em não usar ANY em algum lugar, pois 1km vinha rodando bem!
SELECT geo_uri, id_unico,
  id_unico=grid_ibge.gid_to_name(gid_new) AS is_unico,
  nome_1km=grid_ibge.xyLany_to_name(xyLany,5)  AS is_name1km,
  grid_ibge.xyLany_to_name(xyLany,5) as name1km,
  nome_1km
  ,nome_5km=grid_ibge.xyLany_to_name(xyLany,4)  AS is_name5km
  ,nome_10km=grid_ibge.xyLany_to_name(xyLany,3)  AS is_name10km
  ,nome_50km=grid_ibge.xyLany_to_name(xyLany,2)  AS is_name50km
--  ,nome_100km=grid_ibge.xyLany_to_name(xyLany,1)  AS is_name100km
--  ,nome_500km=grid_ibge.xyLany_to_name(xyLany,0)  AS is_name500km
FROM (
  -- CUIDADO, JOIN funcionando só para pontos distantes mais de 1km ou 200m entre si.
  SELECT c.gid as gid_new, s.*, grid_ibge.gid_to_xyLcenter(c.gid) xyLany -- nâo pode ser xyLref pois borda dá erro no 200.
  FROM grid_ibge.mvw_homolog_sample_pt s INNER JOIN grid_ibge.censo2010_info c
    ON c.gid = grid_ibge.name_to_gid(s.id_unico)
) t1;

-- Testa conversão direta da geoURI:
SELECT geo_uri,id_unico,
 id_unico=CASE WHEN id_unico!=nome_1km THEN grid_ibge.gid_to_name(grid_ibge.geoURI_to_gid(geo_uri,6)) ELSE NULL END AS is_name200m,
 nome_1km = grid_ibge.gid_to_name(grid_ibge.geoURI_to_gid(geo_uri))  AS is_name1km,
 nome_5km = grid_ibge.gid_to_name(grid_ibge.geoURI_to_gid(geo_uri,4))  AS is_name5km,
 nome_10km = grid_ibge.gid_to_name(grid_ibge.geoURI_to_gid(geo_uri,3))  AS is_name10km,
 nome_50km = grid_ibge.gid_to_name(grid_ibge.geoURI_to_gid(geo_uri,2))  AS is_name50km,
 nome_100km = grid_ibge.gid_to_name(grid_ibge.geoURI_to_gid(geo_uri,1)) AS is_name100km,
 nome_500km = grid_ibge.gid_to_name(grid_ibge.geoURI_to_gid(geo_uri,0)) AS is_name500km
FROM (
 -- CUIDADO, JOIN funcionando só para pontos distantes mais de 1km ou 200m entre si.
 SELECT c.gid as gid_new, s.*, grid_ibge.gid_to_xyLcenter(c.gid) xyL_1km
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
-- -- GEOMETRIA: mais testes, agora homologando geometria das células

SELECT BOOL_AND( round(st_area(st_intersection(albers_geom,new_geom)))=round(ST_area(geom,true))  ) as interecs_areas1,
       BOOL_AND(st_contains(geom,pt_geom)) contains_pt_geom1
FROM (
  SELECT c.gid, s.geom, s.pt_geom, grid_ibge.draw_cell(c.gid) as new_geom, ST_Transform(s.geom,952019) as albers_geom
  FROM grid_ibge.mvw_homolog_sample_pt s INNER JOIN grid_ibge.censo2010_info c
    ON c.gid = grid_ibge.name_to_gid(s.id_unico)
) t1;

SELECT BOOL_AND( round(st_area(st_intersection(albers_geom,new_geom)))=round(ST_area(geom,true))  ) as interecs_areas2
FROM (
  SELECT *, ST_Transform(geom,952019) as albers_geom,
        grid_ibge.draw_cell( grid_ibge.name_to_gid(id_unico) ) as new_geom
  FROM grade_all_ids_sample
) t;

-- contabiliza a chance de "falha" nas bordas: ~25% = ~1/4.
SELECT -- SUM(n) n_tot,
       round(100.0*SUM(n) FILTER (WHERE contains_pt_geom ) / SUM(n)) AS contains_pt_geom_perc,
       round(100.0*SUM(n) FILTER (WHERE contains_center_geom ) / SUM(n)) AS contains_center_geom_perc
FROM (
  SELECT ST_Contains(new_geom,pt_geom) AS contains_pt_geom,
         ST_Contains(new_geom,ptcenter) AS contains_center_geom, count(*) n
  FROM (
    SELECT id_unico, g.geom as pt_geom, ST_Transform( st_centroid(t.geom), 952019) as ptCenter,
           grid_ibge.draw_cell( grid_ibge.name_to_gid(id_unico) ) as new_geom
    FROM grade_all_ids_sample t, LATERAL ST_DumpPoints( ST_Transform( st_simplify(t.geom,0.00001),952019) ) g
  ) t1 GROUP BY 1, 2 ORDER BY 1,2  -- com ou sem ST_simplify o efeito é o mesmo.
) t2;

-----------

/* to generate sample set!
COPY (
  SELECT jurisdiction, name, geo_uri, wikidata_id, osm_node_id, id_unico as  ibge_cell_nome
  FROM grid_ibge.mvw_homolog_sample_pt
) TO '/tmp/ptCtrl2.csv' CSV HEADER;
*/

-- SELECT grid_ibge.drop_original();
