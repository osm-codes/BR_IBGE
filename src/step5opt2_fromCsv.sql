--
-- Grade IBGE em uma nova representação, ingestão a partir da grade original. Ver makefile para o processo completo.
--

-- -- -- -- -- -- -- -- -- -- --
-- Processo de ingestão do zip, ver make get_zcompact:

DELETE FROM grid_ibge.censo2010_info;

COPY grid_ibge.censo2010_info FROM '/tmp/grid_ibge_censo2010_info.csv' CSV HEADER;

--------------------------------------
--- RELATÓRIO DOS DADOS INGERIDOS: ---
-- Volumetria comparativa:
SELECT resource, tables, tot_bytes, pg_size_pretty(tot_bytes) tot_size,
       tot_lines, round(tot_bytes/tot_lines) AS bytes_per_line
FROM (
  SELECT 'Grade compacta' AS resource, 1 AS tables,
         pg_relation_size('grid_ibge.censo2010_info') AS tot_bytes,
         pg_relation_lines('grid_ibge.censo2010_info') AS tot_lines
) t;
-- Células por nível:
SELECT grid_ibge.gid_to_level(gid) as nivel, COUNT(*) n_compact_cells
FROM grid_ibge.censo2010_info
GROUP BY 1 ORDER BY 1;

------------------
--- REFRESHES: ---
REFRESH MATERIALIZED VIEW  grid_ibge.mvw_censo2010_info_Xsearch;  -- pode levar horas!
REFRESH MATERIALIZED VIEW  grid_ibge.mvw_censo2010_info_Ysearch;  -- pode levar horas!

SELECT min(x) x_min, max(x) x_max FROM grid_ibge.mvw_censo2010_info_Xsearch;
SELECT min(y) y_min, max(y) y_max FROM grid_ibge.mvw_censo2010_info_Ysearch;
