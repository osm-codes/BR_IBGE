/*
 * ASSERTs - Testes de Regressão
 */

DO $tests$
begin
  RAISE NOTICE '1. Testando conversões de nível hierárquico...';
  ASSERT grid_ibge.level_to_size(0)=500000,     '1.1. Nivel 0 tem 500KM de lado';
  ASSERT grid_ibge.level_to_size(6)=200,        '1.2. Nivel 6 tem 200M de lado';
  ASSERT grid_ibge.prefix_to_level('500KM')=0,  '1.3. 500KM é o nível 0';
  ASSERT grid_ibge.prefix_to_level('200M')=6,   '1.4. 200M é o nível 6';
  ASSERT grid_ibge.level_to_prefix(1)='100KM',  '1.5. Prefixo de L1 é 100KM';
  ASSERT grid_ibge.level_to_prefix(5)='1KM',    '1.6. Prefixo de L5 é 1KM';
  ASSERT grid_ibge.gid_to_level(5300000096300004::bigint)=4, '1.7. Nível hierárquico da célula gid';
  ASSERT grid_ibge.name_to_parts_normalized('5KME5300N9630')=array[4,5300000,9630000], '1.8. name_to_parts_normalized';

  RAISE NOTICE '2. Testando conversões de gid, nome e ponto de célula...';
  ASSERT grid_ibge.name_to_parts('5KME5300N9630')='{5KM,5300,9630}'::text[],  '2.1. Partes de 5KME5300N9630';
  ASSERT grid_ibge.ptcenter_to_ptref(5302500,9632500,4)='{5300000,9630000,4,2500}'::int[], '2.2. ptcenter_to_ptref';
  ASSERT grid_ibge.name_to_gid('5KME5300N9630')=5300000096300004::bigint,           '2.3. gid de 5KME5300N9630';
  ASSERT grid_ibge.gid_to_ptref(5300000096300004)='{5300000,9630000,4}'::int[],     '2.4. Coordenadas (do ponto de referência) e nível do gid 5300000096300004';
  ASSERT grid_ibge.gid_to_ptcenter(5300000096300004)='{5302500,9632500,4}'::int[],  '2.5. Coordenadas (do ponto central) e nível do gid 5300000096300004';
  ASSERT grid_ibge.ptcenter_to_gid(5302500,9632500,4)=5300000096300004::bigint,     '2.6. ptcenter_to_gid';

  RAISE NOTICE '3. Testando busca de célula contendo ponto...';
  ASSERT grid_ibge.search_cell_bylatlon(-23.550278,-46.633889,1)=5700000086500001::bigint,  '3.1. search_cell_bylatlon ponto ';
  ASSERT grid_ibge.search_cell('geo:-23.550278,-46.633889',1)=5700000086500001::bigint,     '3.2. search_cell GeoURI';
  ASSERT grid_ibge.search_cell_bylatlon(-23.550278,-46.633889,6)=5756000087008006::bigint,  '3.3. search_cell_bylatlon ponto ';

  --RAISE NOTICE '4. Testando decodificação para geometria da célula...';
  ---
end;
$tests$ LANGUAGE plpgsql;


/*  TESTE VISUAL NO QGIS:
DROP TABLE test01_marcozero_l6;
DROP TABLE test01_marcozero_l5;
DROP TABLE test02_sul1_id04;
DROP TABLE test05_level1;
DROP TABLE test06_level0;

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
*/
