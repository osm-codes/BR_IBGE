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
  ASSERT grid_ibge.name_to_parts('5KME5300N9630')='{5KM,5300,9630}'::text[],        '2.1. Partes de 5KME5300N9630';
  ASSERT grid_ibge.xyLcenter_to_xyLref(5302500,9632500,4)='{5300000,9630000,4,2500}'::int[], '2.2. xyLcenter_to_xyLref';
  ASSERT grid_ibge.name_to_gid('5KME5300N9630')=5300000096300004::bigint,           '2.3. gid de 5KME5300N9630';
  ASSERT grid_ibge.gid_to_xyLref(5300000096300004)='{5300000,9630000,4}'::int[],    '2.4. Coordenadas (do ponto de referência) e nível do gid 5300000096300004';
  ASSERT grid_ibge.gid_to_xyLcenter(5300000096300004)='{5302500,9632500,4}'::int[], '2.5. Coordenadas (do ponto central) e nível do gid 5300000096300004';
  ASSERT grid_ibge.xyLcenter_to_gid(5302500,9632500,4)=5300000096300004::bigint,    '2.6. xyLcenter_to_gid';
  ASSERT grid_ibge.gid_to_name(5300000096300004::bigint)='5KME5300N9630',           '2.7. gid_to_name 5KM';
  ASSERT grid_ibge.gid_to_name(5700000086500001::bigint)='100KME5700N8650',         '2.8. gid_to_name 100KM';
  ASSERT grid_ibge.gid_to_name(4982000078122006::bigint)='200ME49820N78122',        '2.9. gid_to_name 200M';

  RAISE NOTICE '3. Testando busca de célula contendo ponto...';
  --ASSERT grid_ibge.search_cell_bylatlon(-23.550278,-46.633889,1)=5700000086500001::bigint,  '3.1. search_cell_bylatlon ponto ';
  --ASSERT grid_ibge.search_cell('geo:-23.550278,-46.633889',1)=5700000086500001::bigint,     '3.2. search_cell GeoURI';
  --ASSERT grid_ibge.search_cell_bylatlon(-23.550278,-46.633889,6)=5756000087008006::bigint,  '3.3. search_cell_bylatlon ponto ';

  --RAISE NOTICE '4. Testando decodificação para geometria da célula...';
  ---
end;
$tests$ LANGUAGE plpgsql;


/*
 * QGIS data visualization
 */

CREATE or replace VIEW vw_grid_ibge_l0 AS
  SELECT *, grid_ibge.gid_to_name(gid) id_unico, grid_ibge.draw_cell(gid) geom
  FROM grid_ibge.censo2010_info WHERE gid&7=0
;
CREATE or replace VIEW vw_grid_ibge_l1 AS
  SELECT *, grid_ibge.gid_to_name(gid) id_unico, grid_ibge.draw_cell(gid) geom
  FROM grid_ibge.censo2010_info WHERE gid&7=1
;
/* gravando views como texto GeoJSON.
write_grid_ibge500km e write_grid_ibge100km:
SELECT write_geojson_Features(
  'vw_grid_ibge_l0'
  '/tmp/grid_ibge500km.geojson',
  'ST_Transform(t1.geom,4326)',
  'id_unico,pop,pop_fem_perc,dom_ocu',
  array['gid'],
  'gid'
);
SELECT write_geojson_Features(
  'vw_grid_ibge_l1'
  '/tmp/grid_ibge100km.geojson',
  'ST_Transform(t1.geom,4326)',
  'id_unico,pop,pop_fem_perc,dom_ocu',
  array['gid'],
  'gid'
);
*/
