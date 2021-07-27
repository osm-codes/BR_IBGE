
--- pontos conhecidos


CREATE TABLE test01_marcozero AS
  SELECT gid, grid_ibge.gid_to_ptcenter(gid) center, grid_ibge.draw_cell(gid) geom
  FROM (
      SELECT grid_ibge.search_cell_bylatlon(-23.550278,-46.633889,l) gid
      FROM generate_series(0,6) t1(l)
  ) t2
;
CREATE TABLE test02_sul1_id04 AS
  SELECT gid, grid_ibge.gid_to_ptcenter(gid) center, grid_ibge.draw_cell(gid) geom
  FROM (
      SELECT grid_ibge.search_cell_bylatlon(-31.7606,-52.4105,l) gid
      FROM generate_series(0,6) t1(l)
  ) t2
;
SELECT

DROP TABLE test01_marcozero_l6;
DROP TABLE test01_marcozero_l5;
DROP TABLE test02_sul1_id04;

CREATE TABLE test01_marcozero_l6 AS
  SELECT gid, grid_ibge.draw_cell(gid) geom
  FROM (
      SELECT grid_ibge.search_cell_bylatlon(-23.550278,-46.633889,6) gid
  ) t2
;


CREATE TABLE test01_marcozero_l5 AS
  SELECT 1 as gid, grid_ibge.draw_cell(5756000,8700600,500) geom
;

DROP TABLE test01_marcozero;
CREATE TABLE test01_marcozero AS
  SELECT gid, grid_ibge.draw_cell(gid) geom
  FROM grid_ibge.censo2010_info
  WHERE gid IN (
    5756000008700800006::bigint, 5756000008701000006::bigint, 5756000008701000005::bigint, 5756000008702000005::bigint,
    5800000008550000001::bigint, 5800000008650000001::bigint
  )
;

DROP TABLE test06_level0;
DROP TABLE test05_level1;


--- 5756000008700800006 | POLYGON((5756000 8700600,5756000 8700800,5756200 8700800,5756200 8700600,5756000 8700600))
