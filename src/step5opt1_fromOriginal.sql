--
-- Grade IBGE em uma nova representação, ingestão a partir da grade original. Ver makefile para o processo completo.
--

-- -- -- -- -- -- -- -- -- -- --
-- Processo de ingestão completo:

CREATE or replace FUNCTION grid_ibge.censo2010_info_load(
  p_tabgrade text,
  p_add_levels boolean DEFAULT false
) RETURNS text AS $f$
DECLARE
  r0 int;
  nivel int;
  q0 text;
  qsub text :='';
BEGIN
  RAISE NOTICE ' Processando % ...', p_tabgrade;
  FOR nivel IN REVERSE 4..0 LOOP
    -- sumarização para agregar grades mais grosseiras:
    qsub := qsub  ||  format($$
      UNION ALL
      SELECT grid_ibge.name_to_gid(nome) as gid,
             pop::int,
             round(CASE WHEN pop>0 THEN 100.0::real*fem/pop ELSE 0.0 END)::smallint AS pop_fem_perc,
             dom_ocu, true AS is_cache
      FROM (
        SELECT %2$s as nome,
               SUM(pop)::real pop, SUM(fem)::real fem, SUM(dom_ocu)::int dom_ocu
        FROM %1$s GROUP BY 1
      ) core_%2$s
    $$,
    p_tabgrade,
    'nome_'||lower(grid_ibge.level_to_prefix( nivel )) -- nome da coluna de sumarização
    );
  END LOOP; -- qsub

  q0 := $$
   WITH coredata AS (
    SELECT grid_ibge.name_to_gid(id_unico) as gid,
         id_unico, quadrante, pop,
         nome_1km, nome_5km, nome_10km, nome_50km, nome_100km, nome_500km, fem,
         substr(id_unico,1,4)='200M' AS is_200m,
         round(CASE WHEN pop>0 THEN 100.0*fem::real/pop::real ELSE 0.0 END)::smallint AS pop_fem_perc,
         dom_ocu,
         false is_cache
    FROM  %3$s
   ),
   ins AS (
   INSERT INTO grid_ibge.censo2010_info(gid, pop, pop_fem_perc, dom_ocu, is_cache)
     SELECT gid, pop, pop_fem_perc, dom_ocu, is_cache
     FROM coredata

     UNION ALL
     -- complementando o 1km:
     SELECT grid_ibge.name_to_gid(nome_1km) as gid,
            pop::int,
            round(CASE WHEN pop>0 THEN 100.0::real*fem/pop ELSE 0.0 END)::smallint AS pop_fem_perc,
            dom_ocu, true AS is_cache -- complementing is cache
     FROM (
       SELECT nome_1km,
              SUM(pop)::real pop, SUM(fem)::real fem, SUM(dom_ocu)::int dom_ocu
       FROM %3$s
       WHERE %1$s AND nome_1km!=id_unico -- only complementing
       GROUP BY nome_1km
     ) core_200m
     --- UNIONS qsub para grades mais grosseiras:
     %2$s
     --------------------------------------------
     ORDER BY 1
   RETURNING 1
   )
   SELECT COUNT(*) FROM ins
 $$;
 q0 = format(q0,  p_add_levels::text,  CASE WHEN p_add_levels THEN qsub ELSE '' END, p_tabgrade);
 --RAISE NOTICE 'SQL = %', format( 'WITH tg AS (SELECT * FROM %s), %s',  p_tabgrade, q0);
 EXECUTE q0 INTO r0;
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
--SELECT grid_ibge.censo2010_info_load('grade_id04',true);  -- false para basico
SELECT grid_ibge.censo2010_info_load(table_name,true) as msg FROM vw_tmp_ibgetabs;

---------------------------------

--- RELATÓRIO DOS DADOS INGERIDOS:

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
SELECT grid_ibge.gid_to_level(gid) as nivel, COUNT(*) n_compact_cells
FROM grid_ibge.censo2010_info
GROUP BY 1 ORDER BY 1;

-- REFRESHES:
REFRESH MATERIALIZED VIEW  grid_ibge.mvw_censo2010_info_Xsearch;
REFRESH MATERIALIZED VIEW  grid_ibge.mvw_censo2010_info_Ysearch;

SELECT min(x) x_min, max(x) x_max FROM grid_ibge.mvw_censo2010_info_Xsearch;
SELECT min(y) y_min, max(y) y_max FROM grid_ibge.mvw_censo2010_info_Ysearch;

-----------
-- LIMPEZA:
--   DROP das tabelas listadas em vw_tmp_ibgetabs;
--   DROP FUNCTION grid_ibge.censo2010_info_load;
--   DROP VIEW vw_tmp_ibgetabs;

-- COPY (SELECT * FROM grid_ibge.censo2010_info ORDER BY gid&7, gid) TO '/tmp/grid_ibge_censo2010_info.csv' CSV HEADER;

/*
resource       | tables | tot_bytes  | tot_size | tot_lines | bytes_per_line
---------------------+--------+------------+----------+-----------+----------------
Grade IBGE original |     56 | 4311826432 | 4112 MB  |  13286489 |            325
Grade compacta      |      1 |  726556672 | 693 MB   |  13924454 |             52
(2 rows)

ibge=#
ibge=# -- Células por nível:
ibge=# SELECT grid_ibge.gid_to_level(gid) as nivel, COUNT(*) n_compact_cells
ibge-# FROM grid_ibge.censo2010_info
ibge-# GROUP BY 1 ORDER BY 1;
nivel | n_compact_cells
-------+-----------------
0 |              56
1 |            1000
2 |            3802
3 |           90624
4 |          358069
5 |         8860553
6 |         4610350
(7 rows)

ibge=# SELECT min(x) x_min, max(x) x_max FROM grid_ibge.mvw_censo2010_info_Xsearch;
  x_min  |  x_max
---------+---------
 2805000 | 7650000
(1 row)

ibge=# SELECT min(y) y_min, max(y) y_max FROM grid_ibge.mvw_censo2010_info_Ysearch;
  y_min  |  y_max
---------+----------
 7575000 | 12100000
(1 row)

*/
