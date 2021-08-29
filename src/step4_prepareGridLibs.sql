--
-- Grade IBGE em uma nova representação, minimalista, mais leve para o banco de dados, e com "custo geometria" opcional.
-- Algoritmo de busca orientado à representação por coordenadas XY dos centroides das células da grade.
--

-- -- -- --
-- Operações de preparo, não precisam ser repetidas, podem ser removidas destescript:

CREATE extension IF NOT EXISTS postgis;
DROP SCHEMA IF EXISTS grid_ibge CASCADE;
CREATE SCHEMA IF NOT EXISTS grid_ibge;

-----

CREATE TABLE grid_ibge.censo2010_info (
  gid bigint NOT NULL PRIMARY KEY,  -- valif for all levels
  pop int NOT NULL,   -- can be SUM()
  pop_fem_perc smallint NOT NULL, -- CHECK(pop_fem_perc BETWEEN 0 AND 100),
  dom_ocu int NOT NULL, -- can be a SUM()
  is_cache boolean NOT NULL DEFAULT true
  --, has_urban boolean -- for aggregated levels and 200m occupation class
  -- or info JSONb ...Check memory usage and need for optional informations
);
COMMENT ON TABLE grid_ibge.censo2010_info
  IS 'Informações do Censo de 2010 organizadas pela Grade Estatística do IBGE, com células codificadas em 4+30+30 bits do identificador gid'
;
COMMENT ON COLUMN grid_ibge.censo2010_info.gid IS 'ID com informação embutida (1+3 bits do nível da grade e 30+30 bits para XY do centroide da célula)';
COMMENT ON COLUMN grid_ibge.censo2010_info.pop IS 'População total dentro da célula';
COMMENT ON COLUMN grid_ibge.censo2010_info.pop_fem_perc IS 'Percentual da população feminina';
COMMENT ON COLUMN grid_ibge.censo2010_info.dom_ocu IS 'Domicílios ocupados - particulares permanentes, particulares improvisados e coletivos';

------

CREATE FUNCTION grid_ibge.level_to_size(level int)  RETURNS int AS $f$
  SELECT (array[500000, 100000, 50000, 10000, 5000, 1000, 200])[level+1]
  -- colnames array['nome_5km','nome_10km','nome_50km','nome_100km','nome_500km'];
$f$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION grid_ibge.level_to_size(int)
  IS 'Converts level number convention (IBGEs grid hierarchical level) into size of the cell side, in meters.'
;
CREATE FUNCTION grid_ibge.prefix_to_level(prefix text) RETURNS int AS $f$
  SELECT array_position(array['500KM','100KM','50KM','10KM','5KM','1KM','200M'],prefix) - 1;
$f$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION grid_ibge.prefix_to_level
  IS 'Converts original prefix (used in id_unico) into level number (IBGEs grid hierarchical level).'
;
CREATE FUNCTION grid_ibge.level_to_prefix(level int) RETURNS text AS $f$
  SELECT (array['500KM','100KM','50KM','10KM','5KM','1KM','200M'])[level + 1];
$f$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION grid_ibge.level_to_prefix
  IS 'Converts level number (IBGEs grid hierarchical level) to original prefix used in id_unico.'
;


CREATE FUNCTION grid_ibge.name_to_parts(name text) RETURNS text[] AS $f$
  SELECT regexp_matches(name, '(\d+(?:M|KM))E(\d+)N(\d+)')
$f$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION grid_ibge.name_to_parts
  IS 'Splits IBGE cell name string into its 3 parts.'
;

CREATE FUNCTION grid_ibge.name_to_gid(name text) RETURNS bigint AS $f$
  SELECT (
    rpad(p[2], 7, '0') -- X
    || CASE WHEN substr(p[3],1,1)='1' THEN rpad(p[3],8,'0') ELSE '0'||rpad(p[3],7,'0') END -- Y
    || grid_ibge.prefix_to_level(p[1]) -- level
  )::bigint
  FROM ( SELECT grid_ibge.name_to_parts(name) p ) t
$f$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION grid_ibge.name_to_gid
  IS 'Converts IBGE original cell-name string into Bigint gid.'
;

CREATE or replace FUNCTION grid_ibge.gid_to_ptref(gid bigint) RETURNS int[] AS $f$
  -- X,Y,Level. Falta testar opções de otimização, como floor(gid/100000000000::bigint) as x
  SELECT array[ substr(p,1,7)::int, substr(p,8,8)::int, (gid & 7::bigint)::int ]
  FROM ( SELECT gid::text p ) t
$f$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION grid_ibge.gid_to_ptref
  IS 'Converts Bigint gid into reference-point XY Albers, and Level of the cell.'
;

CREATE or replace FUNCTION grid_ibge.gid_to_name(gid bigint) RETURNS text AS $f$
  SELECT grid_ibge.level_to_prefix((gid & 7::bigint)::int)
         ||'E'|| substr(p,1,digits)  -- full=substr(p,1,7)
         ||'N'|| substr( (substr(p,8,digits+1)::int)::text, 1, digits)   -- full=substr(p,8,8)
  FROM (
    SELECT p, CASE WHEN digits=4 AND substr(p,8,1)='1' THEN 5 ELSE digits END AS digits
    FROM ( SELECT gid::text p, CASE WHEN gid&7=6 THEN 5 ELSE 4 END AS digits ) t1
  ) t2
$f$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION grid_ibge.gid_to_ptref
  IS 'Converts Bigint gid into original IBGE cell-name.'
;

CREATE FUNCTION grid_ibge.gid_to_ptcenter(gid bigint) RETURNS int[] AS $f$
  -- X,Y,Level. Falta testar opções de otimização, como floor(gid/1000000000000::bigint) as x
  SELECT CASE
    WHEN L=6 THEN array[ x_ref+halfside, y_ref-halfside, L ]
    ELSE          array[ x_ref+halfside, y_ref+halfside, L ]
    END
  FROM (
    SELECT p[1] as x_ref, p[2] as y_ref, p[3] as L,
           grid_ibge.level_to_size(p[3])/2::int as halfside
    FROM ( SELECT grid_ibge.gid_to_ptref(gid) p ) t1
  ) t2
$f$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION grid_ibge.gid_to_ptcenter
  IS 'Converts Bigint gid into center-XY Albers, and Level of the cell.'
;

CREATE FUNCTION grid_ibge.ptcenter_to_ptref(x int, y int, nivel int) RETURNS int[] AS $f$
  -- descartar halfside, ninguém tá usando.
  SELECT CASE
    WHEN nivel=6 THEN array[ x-halfside, y+halfside, nivel, halfside ]
    ELSE              array[ x-halfside, y-halfside, nivel, halfside ]
    END
  FROM ( SELECT grid_ibge.level_to_size(nivel)/2::int as halfside ) t
$f$ LANGUAGE SQL IMMUTABLE;

CREATE or replace FUNCTION grid_ibge.ptcenter_to_gid(x int, y int, nivel int) RETURNS bigint AS $f$
  SELECT (
    rpad(p[1], 7, '0') -- X
    || CASE WHEN substr(p[2],1,1)='1' THEN rpad(p[2],8,'0') ELSE '0'||rpad(p[2],7,'0') END -- Y
    || p[3] -- level
  )::bigint
  FROM ( SELECT grid_ibge.ptcenter_to_ptref(x,y,nivel)::text[] ) t(p)
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION grid_ibge.gid_to_level(gid bigint) RETURNS int AS $f$
  SELECT (gid & 7::bigint)::int
$f$ LANGUAGE SQL IMMUTABLE;


---------!!!!!!!!!!!!!!!!!!!
-- 1. falta encode de coordenada no lugar de name, aí fazendo o devido arredondamento e equação de célula. Por exemplo 200M e 1KM usam diferentes.
-- 2. falta decode de GID em centro de célula que é diferente de decode nas partes!
-- 3. Eliminar o *10 !
-- 4. testar o draw_cell primeiro em grade_id04 com 200M e 1KM ... depois o resto.
-- 5. testar o draw_cell_snaptogrid para valores interiores sempre cairem no centro.

-- LIXO: revisar código (chamar demais funções) ou descartar.
CREATE FUNCTION grid_ibge.name_to_parts_normalized(name text) RETURNS int[] AS $f$
  SELECT array[
    grid_ibge.prefix_to_level(p[1]),
    rpad(p[2], 7, '0')::int, -- X range into (28093700,75992710).
    rpad(p[3], CASE WHEN substr(p[3],1,1)='1' THEN 8 ELSE 7 END, '0')::int -- Y into (76207280,119206110).
  ]
  FROM ( SELECT grid_ibge.name_to_parts(name) p ) t
$f$ LANGUAGE SQL IMMUTABLE;
CREATE FUNCTION grid_ibge.name_to_center(name text) RETURNS int[] AS $f$
  -- FALTA refazer com base em gid_to_ptcenter()  e encode.
  SELECT CASE
    WHEN L=6 THEN array[ x_ref+halfside, y_ref-halfside, L ]
    ELSE          array[ x_ref+halfside, y_ref+halfside, L ]
    END
  FROM (
    SELECT p[1] as L, p[2] as x_ref, p[3] as y_ref,
           grid_ibge.level_to_size(p[1])/2::int as halfside
    FROM ( SELECT grid_ibge.name_to_parts_normalized(name) p ) t1
  ) t2
$f$ LANGUAGE SQL IMMUTABLE;

---------------

CREATE MATERIALIZED VIEW grid_ibge.mvw_censo2010_info_Xsearch AS
  SELECT DISTINCT xyL[3]::smallint as level, xyL[1] AS x
  FROM (
    SELECT grid_ibge.gid_to_ptcenter(gid) AS xyL FROM grid_ibge.censo2010_info
  ) t
;
CREATE INDEX mvw_censo2010_info_xsearch_xbtree ON grid_ibge.mvw_censo2010_info_Xsearch(level,x);

CREATE MATERIALIZED VIEW grid_ibge.mvw_censo2010_info_Ysearch AS
  SELECT DISTINCT xyL[3]::smallint as level, xyL[2] AS y
  FROM (
    SELECT grid_ibge.gid_to_ptcenter(gid) AS xyL FROM grid_ibge.censo2010_info
  ) t
;
CREATE INDEX mvw_censo2010_info_ysearch_ybtree ON grid_ibge.mvw_censo2010_info_Ysearch(level,y);

-----
CREATE FUNCTION grid_ibge.search_xyL(p_x int, p_y int, p_level smallint) RETURNS int[] AS $f$
   -- a busca parte da presunção de existência, ou seja, ponto dentro da grade.
   SELECT array[t1x.x, t1y.y, p_level::int]
   FROM (
    SELECT x FROM (
      (
        SELECT x
        FROM grid_ibge.mvw_censo2010_info_Xsearch
        WHERE level=p_level AND x >= p_x
        ORDER BY x LIMIT 1
      )  UNION ALL (
        SELECT x
        FROM grid_ibge.mvw_censo2010_info_Xsearch
        WHERE level=p_level AND x < p_x
        ORDER BY x DESC LIMIT 1
      )
    ) t0x
    ORDER BY abs(p_x-x) LIMIT 1
  ) t1x, (
    SELECT y FROM (
      (
        SELECT y
        FROM grid_ibge.mvw_censo2010_info_Ysearch
        WHERE level=p_level AND y >= p_y
        ORDER BY y LIMIT 1
      )  UNION ALL (
        SELECT y
        FROM grid_ibge.mvw_censo2010_info_Ysearch
        WHERE level=p_level AND y < p_y
        ORDER BY y DESC LIMIT 1
      )
    ) t0y
    ORDER BY abs(p_y-y)
    LIMIT 1
  ) t1y
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION grid_ibge.search_xyL_bylatlon(
  lat real, lon real, p_level int
) RETURNS int[] AS $f$
  SELECT grid_ibge.search_xyL(ST_X(geom)::int, ST_Y(geom)::int, p_level::smallint)
  FROM (SELECT ST_Transform( ST_SetSRID( ST_MakePoint(lon,lat),4326), 952019 )) t(geom);
$f$ LANGUAGE SQL IMMUTABLE;
-- select grid_ibge.search_xyL_bylatlon(-23.550278::real,-46.633889::real,6::smallint);

CREATE FUNCTION grid_ibge.search_xyL(geoURI text, p_level int DEFAULT 5) RETURNS int[] AS $wrap$
  SELECT grid_ibge.search_xyL_bylatlon( p[1]::real, p[2]::real, p_level )
  FROM ( SELECT regexp_match(geoURI,'^geo:([+\-]?\d+\.?\d*),([+\-]?\d+\.?\d*)(?:;.+)?$') ) t(p);
$wrap$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION grid_ibge.search_to_gid(p_x int, p_y int, p_level smallint) RETURNS bigint AS $f$
  SELECT grid_ibge.ptcenter_to_gid(p[1], p[2], p_level)
  FROM ( SELECT grid_ibge.search_xyL(p_x, p_y, p_level) ) t(p)
$f$ LANGUAGE SQL IMMUTABLE;

-- CREATE FUNCTION grid_ibge.gid_contains(gid bigint, gid_into bigint) RETURNS bigint
-- drop FUNCTION grid_ibge.search_cell;
CREATE FUNCTION grid_ibge.search_cell(p_x real, p_y real, p_level smallint) RETURNS bigint AS $wrap$
  SELECT grid_ibge.search_to_gid( round(p_x)::int, round(p_y)::int, p_level );
$wrap$ LANGUAGE SQL IMMUTABLE;
-- precisa? grid_ibge.search_snapcell para arredondar conforme o nível.

--DROP grid_ibge.search_cell_bylatlon;
CREATE FUNCTION grid_ibge.search_cell_bylatlon(
  lat real, lon real, p_level int
) RETURNS bigint AS $f$
  SELECT grid_ibge.search_cell(ST_X(geom)::real, ST_Y(geom)::real, p_level::smallint)
  FROM (SELECT ST_Transform( ST_SetSRID( ST_MakePoint(lon,lat),4326), 952019 )) t(geom);
$f$ LANGUAGE SQL IMMUTABLE;
-- select grid_ibge.search_cell_bylatlon(-23.550278::real,-46.633889::real,6::smallint);

CREATE FUNCTION grid_ibge.search_cell(geoURI text, p_level int DEFAULT 5) RETURNS bigint AS $wrap$
  SELECT grid_ibge.search_cell_bylatlon( p[1]::real, p[2]::real, p_level )
  FROM ( SELECT regexp_match(geoURI,'^geo:([+\-]?\d+\.?\d*),([+\-]?\d+\.?\d*)(?:;.+)?$') ) t(p);
  -- exemplo de opções para split(';')  'crs=BR_ALBERS_IBGE;u=200'
  -- FALTA snap Uncertainty to level
$wrap$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION grid_ibge.search_cell_bylatlon(lat numeric, lon numeric, p_level int) RETURNS bigint AS $wrap$
  SELECT grid_ibge.search_cell_bylatlon(lat::real,lon::real,p_level)
$wrap$ LANGUAGE SQL IMMUTABLE;
CREATE FUNCTION grid_ibge.search_cell_bylatlon(lat float, lon float, p_level int) RETURNS bigint AS $wrap$
  SELECT grid_ibge.search_cell_bylatlon(lat::real,lon::real,p_level)
$wrap$ LANGUAGE SQL IMMUTABLE;
-- select grid_ibge.search_cell_bylatlon(-23.550278,-46.633889,6);


-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Reproduzindo a grade original a partir da compacta:

CREATE FUNCTION grid_ibge.uncertain_to_size(u int) RETURNS int AS $f$
  -- GeoURI's uncertainty value "is the radius of the disk that represents uncertainty geometrically"
  SELECT CASE -- discretization by "snap to size-levels"
     WHEN s<500    THEN 200
     WHEN s<2500   THEN 1000
     WHEN s<5000   THEN 5000
     WHEN s<25000  THEN 10000
     WHEN s<50000  THEN 50000
     WHEN s<250000 THEN 100000
     ELSE               500000
   FROM (SELECT u*2) t(s)
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION grid_ibge.xys_to_ijs(x int, y int, s int) RETURNS int[] AS $f$
  SELECT array[ (x-2800000)/s, (y-7350000)/s, s ] -- ex.s=500000
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION grid_ibge.xyL_to_ijs(x int, y int, L int) RETURNS int[] AS $f$
  SELECT grid_ibge.xys_to_ijs(x,y,s)
  FROM ( SELECT level_to_size(L) ) t(s)
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION grid_ibge.ijS_to_cellref(i int, j int, s int) RETURNS int[] AS $f$
  SELECT array[ 2800000 + i*s, 7350000 + j*s, s ]
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION grid_ibge.xyL_to_cellref(x int, y int, L int DEFAULT 0) RETURNS int[] AS $f$
  SELECT grid_ibge.ijS_to_cellref(ijs[1], ijs[2], ijs[3])
  FROM ( SELECT xyL_to_ijS(x,y,L) ) t(ijs)
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION grid_ibge.xyL_to_cellcenter(x int, y int, L int DEFAULT 0) RETURNS int[] AS $f$
  SELECT array[ xyL[1]+h, xyL[2]+h, xyL[3] ]
  FROM ( SELECT grid_ibge.xyL_to_cellref(x,y,L), L/2 ) t(xyL,h)
$f$ LANGUAGE SQL IMMUTABLE;


CREATE FUNCTION grid_ibge.xy_to_quadrante(x int, y int) RETURNS int AS $f$
  -- Integer arithmetic:
  SELECT 10*( (y-7350000)/500000 ) + (x-2800000)/500000
  -- Real arithmetic:
  -- SELECT 10*floor( (y-7350000)::real/500000::real )::int
  --        + floor( (x-2800000)::real/500000::real )::int
  -- Na cobertura `(Xmin,Ymin)=(2809500,7599500)` e `(Xmax,Ymax)=(7620500,11920500)`
  -- Na grade completa? `(Xmin,Ymin)=(2805000,7575000)` e `(Xmax,Ymax)=(7650000,12100000)`
$f$ LANGUAGE SQL IMMUTABLE;

CREATE or replace FUNCTION grid_ibge.quadrantes() RETURNS int[] AS $f$
  SELECT array[
      4,13,14,15,23,24,25,26,27,33,34,35,36,37,39,42,43,44,45,46,47,50,51,52,53,54,55,56,
      57,58,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,80,81,82,83,84,85,92,93
      ]
$f$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION grid_ibge.quadrantes IS 'List of official quadrants.';

CREATE or replace FUNCTION grid_ibge.xy_to_quadrante_valid(x int, y int) RETURNS int AS $wrap$
  SELECT ij
  FROM (SELECT grid_ibge.xy_to_quadrante(x,y)) t(ij)
  WHERE ij = ANY( grid_ibge.quadrantes() )
$wrap$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION grid_ibge.xy_to_quadrante_text(x int, y int, prefix text DEFAULT 'ID_') RETURNS text AS $wrap$
  SELECT prefix||lpad(grid_ibge.xy_to_quadrante(x,y)::text,2,'0')
$wrap$ LANGUAGE SQL IMMUTABLE;


-- LIXOS para teste:
CREATE or replace FUNCTION grid_ibge.xy_to_quadrante2( x int, y int ) RETURNS int[] AS $f$
DECLARE
  dx0 real; dy0 real; -- deltas
  i0 int; j0 int;   -- level0 coordinates
  ij int;           -- i0 and j0 as standard quadrant-indentifier.
BEGIN
  dx0 := x::real - 2805000::real;  dy0 := y::real - 7575000::real; -- encaixa na box dos quadrantes
  i0 := floor( 10.38::real * dx0/7650000.0::real )::int; -- check range 0 to 9
  j0 := floor( 10::real * dy0/12100000.0::real )::int; -- check range 0 to 9
  RETURN array[i0,j0];
END
$f$ LANGUAGE PLpgSQL IMMUTABLE;

CREATE or replace FUNCTION grid_ibge.xy_to_quadrante3(x int, y int) RETURNS int[] AS $f$
  SELECT array[floor( (y-7350000)::real/500000::real )::int
          , floor( (x-2800000)::real/500000::real )::int]
$f$ LANGUAGE SQL IMMUTABLE;


CREATE or replace FUNCTION grid_ibge.gid_to_quadrante(gid bigint) RETURNS int AS $wrap$
  SELECT grid_ibge.xy_to_quadrante(xyL[1],xyL[2])
  FROM ( SELECT grid_ibge.gid_to_ptcenter(gid) ) t(xyL)
$wrap$ LANGUAGE SQL IMMUTABLE;

------

--DROP  FUNCTION grid_ibge.draw_cell(int,int,int,boolean,int);
CREATE FUNCTION grid_ibge.draw_cell(  -- ok funciona.
  cx int,  -- Center X
  cy int,  -- Center Y
  r int,   -- halfside ou raio do circulo inscrito
  p_translate boolean DEFAULT false, -- true para converter em LatLong (WGS84 sem projeção)
  p_srid int DEFAULT 952019          -- SRID da grade (default IBGE)
) RETURNS geometry AS $f$
SELECT CASE WHEN p_translate THEN ST_Transform(geom,4326) ELSE geom END
FROM (
  SELECT ST_GeomFromText( format(
    'POLYGON((%s %s,%s %s,%s %s,%s %s,%s %s))',
    cx-r,cy-r, cx-r,cy+r, cx+r,cy+r, cx+r,cy-r, cx-r,cy-r
  ), p_srid) AS geom
) t
$f$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION grid_ibge.draw_cell(int,int,int,boolean,int)
  IS 'Draws a square-cell centered on the requested point, with requested radius (half side) and optional translation and SRID.'
;

CREATE or replace FUNCTION grid_ibge.draw_cell( -- by name
  cell_name text,
  p_translate boolean DEFAULT false, -- true para converter em LatLong (WGS84 sem projeção)
  p_srid int DEFAULT 952019          -- SRID da grade (default IBGE)
) RETURNS geometry AS $f$
  SELECT grid_ibge.draw_cell( xyL[1], xyL[2], round(grid_ibge.level_to_size(xyL[3])::real/2.0)::int, $2, $3 )
  FROM (SELECT grid_ibge.name_to_center(cell_name) xyL ) t
$f$ LANGUAGE SQL IMMUTABLE;

CREATE or replace FUNCTION grid_ibge.draw_cell( -- by GID. BUG para 1km
  gid bigint, -- nível e centro XY da célula, codificados no geometricID
  p_translate boolean DEFAULT false, -- true para converter em LatLong (WGS84 sem projeção)
  p_srid int DEFAULT 952019          -- SRID da grade (default IBGE)
) RETURNS geometry AS $wrap$
  SELECT grid_ibge.draw_cell( xyL[1], xyL[2], round(grid_ibge.level_to_size(xyL[3])::real/2.0)::int, $2, $3 )
  FROM (SELECT grid_ibge.gid_to_ptcenter(gid) xyL ) t
$wrap$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION grid_ibge.draw_cell(bigint,boolean,int)
  IS 'Wrap to draw_cell(int,int,*) using gid (embedding XY key) instead coordinates.'
;

----

CREATE or replace FUNCTION grid_ibge.draw_cell_center( -- by name
  cell_name text,
  p_translate boolean DEFAULT false, -- true para converter em LatLong (WGS84 sem projeção)
  p_srid int DEFAULT 952019          -- SRID da grade (default IBGE)
) RETURNS geometry AS $f$
  SELECT CASE WHEN p_translate THEN ST_Transform(geom,4326) ELSE geom END
  FROM (
    SELECT ST_SetSRID( ST_MakePoint(xyL[1],xyL[2]),p_srid) geom
    FROM (SELECT grid_ibge.name_to_center(cell_name) xyL ) t1
  ) t2
$f$ LANGUAGE SQL IMMUTABLE;

CREATE or replace FUNCTION grid_ibge.draw_cell_center( -- by GID
  gid bigint,
  p_translate boolean DEFAULT false, -- true para converter em LatLong (WGS84 sem projeção)
  p_srid int DEFAULT 952019          -- SRID da grade (default IBGE)
) RETURNS geometry AS $f$
  SELECT CASE WHEN p_translate THEN ST_Transform(geom,4326) ELSE geom END
  FROM (
    SELECT ST_SetSRID( ST_MakePoint(xyL[1],xyL[2]),p_srid) geom
    FROM (SELECT grid_ibge.gid_to_ptcenter(gid) xyL ) t1
  ) t2
$f$ LANGUAGE SQL IMMUTABLE;

---------------------------


-- DROP VIEW grid_ibge.vw_original_ibge_rebuild;
CREATE VIEW grid_ibge.vw_original_ibge_rebuild AS
  SELECT gid,
         grid_ibge.gid_to_name(gid) AS id_unico, -- revisar
         -- grid_ibge.gid_to_name(grid_ibge.search_gid_to_gid(gid,5)) 'nome_1km' AS nome_1km,  --revisar
         --grid_ibge.gid_to_quadrante(gid) quadrante, -- revisar
         pop-fem AS masc,
         fem,
         pop,
         dom_ocu,
         grid_ibge.draw_cell(gid) geom
  FROM (
   SELECT *,
          ROUND(pop*pop_fem_perc::real/100.0)::int AS fem
   FROM grid_ibge.censo2010_info
  ) t
;
-- para visualizar no QGIS precisa criar view de um só quadrante para não sobrecarregar.


------------------
--- API:

CREATE SCHEMA IF NOT EXISTS API;

CREATE or replace FUNCTION api.resolver_geo_uri(geouri text) RETURNS JSONb AS $f$
 SELECT jsonb_build_object(
   'BR_IBGE_cell_L0_gid', cell_L0_gid,
   'BR_IBGE_cell_quadrante', lpad( grid_ibge.gid_to_quadrante(cell_L5_gid)::text,2,'0' ),
   'BR_IBGE_cell_L5_gid', cell_L5_gid,
   'BR_IBGE_cell_L0',grid_ibge.gid_to_name( cell_L0_gid ),
   'BR_IBGE_cell_L5',grid_ibge.gid_to_name( cell_L5_gid ),
   'geohash', ST_GeoHash(ST_SetSRID(ST_MakePoint(p[2]::float,p[1]::float),4326), 9),
   'BR_IBGE_cell_L5_censo2010', to_jsonb((
     SELECT jsonb_build_object( 'pop',pop,  'dom_ocu',dom_ocu, 'pop_fem_perc',pop_fem_perc, 'pop_masc_perc',100-pop_fem_perc )
     FROM grid_ibge.censo2010_info
     WHERE gid=cell_L5_gid
    ))
   )
  FROM (
   SELECT p, grid_ibge.search_cell(geouri,0) cell_L0_gid,
          grid_ibge.search_cell(geouri,5) cell_L5_gid
  FROM ( SELECT regexp_match(geoURI,'^geo:([+\-]?\d+\.?\d*),([+\-]?\d+\.?\d*)(?:;.+)?$') ) t1(p)
  ) t2
$f$ LANGUAGE SQL IMMUTABLE;
