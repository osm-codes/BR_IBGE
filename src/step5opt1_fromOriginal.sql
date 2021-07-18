--
-- Grade IBGE em uma nova representação, ingestão a partir da grade original. Ver makefile para o processo completo.
--

-- -- -- -- -- -- -- -- -- -- --
-- Processo de ingestão completo:

CREATE or replace FUNCTION grid_ibge.censo2010_info_load(p_tabgrade text) RETURNS text AS $f$
DECLARE
  q0 text;
  r0 int;
BEGIN
  RAISE NOTICE ' Processando % ...', p_tabgrade;
  q0 := $$
   coredata AS (
    SELECT quadrante, pop,
         substr(id_unico,1,4)='200M' AS is_200m,
         round(CASE WHEN pop>0 THEN 100.0*fem::real/pop::real ELSE 0.0 END)::smallint AS pop_fem_perc,
         dom_ocu,
         ST_X(geom2)::real gx, ST_Y(geom2)::real gy,
         geom
    FROM (
     SELECT *, ST_Transform( ST_Centroid(geom), 952019 ) AS geom2 FROM tg
    ) t
   ),
   ins AS (
   INSERT INTO grid_ibge.censo2010_info(gid, pop, pop_fem_perc, dom_ocu)
     SELECT grid_ibge.coordinate_encode(gx,gy,is_200m), pop, pop_fem_perc, dom_ocu::smallint
     FROM coredata
     ORDER BY 1
   RETURNING 1
   )
   SELECT COUNT(*) FROM ins
 $$;
 EXECUTE format(
    'WITH tg AS (SELECT * FROM %s), %s'
    ,  p_tabgrade, q0
 ) INTO r0;
 -- ... and EXECUTE DROP!
 RETURN p_tabgrade||': '|| r0::text || ' itens inseridos';
END;
$f$ LANGUAGE PLpgSQL;
COMMENT ON FUNCTION grid_ibge.censo2010_info_load
 IS 'Insere todas as células de um quadrante da Grade Estatística IBGE.';

CREATE or replace VIEW vw_tmp_ibgetabs AS
  SELECT  table_name
  FROM information_schema.tables
  WHERE table_schema='public' AND table_name LIKE 'grade_id%'
  ORDER BY table_name
;

--- INGESTÃO:

DELETE FROM grid_ibge.censo2010_info; -- is a refresh, ignores old data.
SELECT grid_ibge.censo2010_info_load(table_name) FROM vw_tmp_ibgetabs;

-- Volumetria comparativa:
SELECT resource, tables, tot_bytes, pg_size_pretty(tot_bytes) tot_size,
       tot_lines, round(tot_bytes/tot_lines) AS bytes_per_line
FROM (
  SELECT 'Grade IBGE original' AS resource, COUNT(*) as tables,
         SUM(pg_relation_size(table_name::regclass)) AS tot_bytes,
         SUM(pg_relation_lines(table_name)) AS tot_lines
  FROM vw_tmp_ibgetabs
  UNION
  SELECT 'Grade compacta', 1,
         pg_relation_size('grid_ibge.censo2010_info'),
         pg_relation_lines('grid_ibge.censo2010_info')
) t;

-- Células por nível:
SELECT grid_ibge.level_decode(gid) as nivel, COUNT(*) n_compact_cells
FROM grid_ibge.censo2010_info
GROUP BY 1 ORDER BY 1;

-- REFRESHES:

REFRESH MATERIALIZED VIEW  grid_ibge.mvw_censo2010_info_Xsearch;
REFRESH MATERIALIZED VIEW  grid_ibge.mvw_censo2010_info_Ysearch;

SELECT min(x10) x10_min, max(x10) x10_max FROM grid_ibge.mvw_censo2010_info_Xsearch;
SELECT min(y10) y10_min, max(y10) y10_max FROM grid_ibge.mvw_censo2010_info_Ysearch;

-----------
-- LIMPEZA:
--   DROP das tabelas listadas em vw_tmp_ibgetabs;
--   DROP FUNCTION grid_ibge.censo2010_info_load;
--   DROP VIEW vw_tmp_ibgetabs;
