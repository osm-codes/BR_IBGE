/**
 * HOMOLOG - Testes sistemáticos ou amostrais para certificar que tudo bate com os shapefiles.
 * PARTE B - "danger" por consumir horas ou dias de sua CPU.
 **/

CREATE MATERIALIZED VIEW grid_ibge.mvw_original_ibge_rebuild_q04 AS
  SELECT gid, -- non-original
         grid_ibge.gid_to_name(gid) AS id_unico,
         grid_ibge.gid_to_name( grid_ibge.gid_to_gid(gid,5) ) AS nome_1km,
         grid_ibge.gid_to_name( grid_ibge.gid_to_gid(gid,4) ) AS nome_5km,
         grid_ibge.gid_to_name( grid_ibge.gid_to_gid(gid,3) ) AS nome_10km,
         grid_ibge.gid_to_name( grid_ibge.gid_to_gid(gid,2) ) AS nome_50km,
         grid_ibge.gid_to_name( grid_ibge.gid_to_gid(gid,1) ) AS nome_100km,
         grid_ibge.gid_to_name( grid_ibge.gid_to_gid(gid,0) ) AS nome_500km,
         grid_ibge.gid_to_quadrante_text(gid) quadrante,
         pop-fem AS masc,
         fem,
         pop,
         dom_ocu,
         grid_ibge.draw_cell(gid) geom
  FROM (
   SELECT *,
          ROUND(pop*pop_fem_perc::real/100.0)::int AS fem
   FROM grid_ibge.censo2010_info
   WHERE NOT(is_cache) -- level>=5 as in original
         AND  grid_ibge.gid_to_quadrante(gid)=4
  ) t
; -- 66031

SELECT COUNT(*) n FROM grade_id04; -- 66031
SELECT ok_nomes, g_ghs=m_ghs as ok_geometries, count(*) as n
FROM (
  SELECT
      m.nome_1km=g.nome_1km AND m.nome_5km=g.nome_5km AND
      m.nome_10km=g.nome_10km AND m.nome_50km=g.nome_50km AND
      m.nome_100km=g.nome_100km AND m.nome_500km=g.nome_500km as ok_nomes,
      st_geohash(st_centroid(g.geom),9) as g_ghs,
      st_geohash(st_centroid(st_transform(m.geom,4326)),9) as m_ghs
  FROM grid_ibge.mvw_original_ibge_rebuild_q04 m -- or full
   INNER JOIN grade_id04 g -- or grade_all_ids_sample
   ON g.id_unico=m.id_unico
) t
GROUP BY 1, 2;  -- t | t | 66031



-- SELECT grid_ibge.drop_original();

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

-- REFRESHES DO "BRUTE FORCE SEARCH":
REFRESH MATERIALIZED VIEW  grid_ibge.mvw_censo2010_info_XbfSearch;  -- pode levar horas!
REFRESH MATERIALIZED VIEW  grid_ibge.mvw_censo2010_info_YbfSearch;  -- pode levar horas!

SELECT min(x) x_min, max(x) x_max FROM grid_ibge.mvw_censo2010_info_XbfSearch;
SELECT min(y) y_min, max(y) y_max FROM grid_ibge.mvw_censo2010_info_YbfSearch;
