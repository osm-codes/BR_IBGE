--
-- Grade IBGE em uma nova representação, minimalista, mais leve para o banco de dados, e com "custo geometria" opcional.
-- Representação orientada às coordenadas XY10 dos centroides das células da grade.
--

-- -- -- --
-- Operações de preparo, não precisam ser repetidas, podem ser removidas destescript:

CREATE extension IF NOT EXISTS postgis;
DROP SCHEMA IF EXISTS grid_ibge CASCADE;
CREATE SCHEMA IF NOT EXISTS grid_ibge;

-----

CREATE TABLE grid_ibge.censo2010_info (
  gid bigint NOT NULL PRIMARY KEY,  --
  pop int NOT NULL,   --
  pop_fem_perc smallint NOT NULL, -- CHECK(pop_fem_perc BETWEEN 0 AND 100), 
  dom_ocu smallint NOT NULL
);
COMMENT ON TABLE grid_ibge.censo2010_info
  IS 'Informações do Censo de 2010 organizadas pela Grade Estatística do IBGE, com células codificadas em 4+30+30 bits do identificador gid'
;
COMMENT ON COLUMN grid_ibge.censo2010_info.gid IS 'ID com informação embutida, nível da grade e centroide da célula';
COMMENT ON COLUMN grid_ibge.censo2010_info.pop IS 'população total dentro da célula';
COMMENT ON COLUMN grid_ibge.censo2010_info.pop_fem_perc IS 'percentual da população feminina';
COMMENT ON COLUMN grid_ibge.censo2010_info.dom_ocu IS 'xxxx';



------

CREATE FUNCTION grid_ibge.coordinate_encode10(x10 bigint, y10 bigint, level int) RETURNS bigint AS $f$
  SELECT (level::bigint <<60) | (x10<<30) | y10
$f$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION grid_ibge.coordinate_encode10(bigint,bigint,int)
  IS 'Encodes two valid-range BigInts (coordinates) into one BigInt (gid)'
;

-- MOST IMPORTANT:
CREATE or replace FUNCTION grid_ibge.coordinate_encode(x real, y real, level int) RETURNS bigint AS $f$
  SELECT grid_ibge.coordinate_encode10(round(x*10)::bigint, round(y*10)::bigint, level)
$f$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION grid_ibge.coordinate_encode(real,real,int)
  IS 'Encodes real coordinates into gid, multiplying each coordinate by 10 before cast'
;
CREATE or replace FUNCTION grid_ibge.coordinate_encode(x real, y real, is_200m boolean) RETURNS bigint AS $f$
  SELECT grid_ibge.coordinate_encode($1, $2, CASE WHEN is_200m THEN 6 ELSE 5 END)
$f$ LANGUAGE SQL IMMUTABLE; -- legado.

/*  -- Debug version:
CREATE or replace FUNCTION grid_ibge.coordinate_encode(x real, y real) RETURNS bigint AS $f$
 DECLARE
   a bigint;
   b bigint;
   mx bigint := (2^30)::bigint;
 BEGIN
  a := round(x*10)::bigint;
  b := round(y*10)::bigint;
  IF a>mx OR b>mx THEN
     RAISE EXCEPTION ' XY10 BIGGER THAN LIMIT %s, See point (%,%)', mx, x,y;
  END IF;
  RETURN grid_ibge.coordinate_encode10(a,b);
 END;
 $f$ LANGUAGE PLpgSQL IMMUTABLE;
*/

CREATE FUNCTION grid_ibge.coordinate_encode10(x10 int, y10 int, level int) RETURNS bigint AS $wrap$
  SELECT grid_ibge.coordinate_encode10(x10::bigint, y10::bigint, level)
$wrap$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION grid_ibge.coordinate_encode10(int,int,int)
  IS 'Encodes two valid-range Integers (level,x10,y10) into one BigInt (gid)'
;

CREATE FUNCTION grid_ibge.coordinate_decode10(gid bigint) RETURNS int[] AS $f$
  SELECT array[ (gid >> 60)::int,  ((gid & 1152921504606846975::bigint) >> 30)::int,  (gid & 1073741823::bigint)::int ]
$f$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION grid_ibge.coordinate_decode10(bigint)
  IS 'Decodes gid into [level,x10,y10].'
;
CREATE FUNCTION grid_ibge.level_decode(gid bigint) RETURNS int AS $f$
  SELECT gid>>60
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION grid_ibge.level_to_size(level int)  RETURNS int AS $f$
  SELECT (array[500000, 100000, 50000, 10000, 5000, 1000, 200])[level+1]
$f$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION grid_ibge.level_to_size(int)
  IS 'Converts level number convention (IBGEs grid hierarchical level) into size of the cell side, in meters.'
;

/* TEST with grade_id45, grade_id04, grade_id60, grade_id69, grade_id93:
 SELECT x,y, gid
 FROM (
  SELECT round( ST_x(geom) )::int x, round( ST_y(geom) )::int y
  FROM ( SELECT ST_Transform(  ST_centroid(geom),  952019) AS geom FROM grade_id45 ) t1
 ) t2, LATERAL grid_ibge.coordinate_decode10(  grid_ibge.coordinate_encode10(x,y)  ) as gid
 WHERE gid[1]!=x OR gid[2]!=y;
*/

CREATE MATERIALIZED VIEW grid_ibge.mvw_censo2010_info_Xsearch AS
  SELECT DISTINCT lxy10[1]::smallint as level, lxy10[2] AS x10
  FROM (
    SELECT grid_ibge.coordinate_decode10(gid) AS lxy10 FROM grid_ibge.censo2010_info
  ) t
;
CREATE INDEX mvw_censo2010_info_xsearch_xbtree ON grid_ibge.mvw_censo2010_info_xsearch(x10);

CREATE MATERIALIZED VIEW grid_ibge.mvw_censo2010_info_Ysearch AS
  SELECT DISTINCT lxy10[1]::smallint as level, lxy10[3] AS y10
  FROM (
    SELECT grid_ibge.coordinate_decode10(gid) AS lxy10 FROM grid_ibge.censo2010_info
  ) t
;
CREATE INDEX mvw_censo2010_info_ysearch_ybtree ON grid_ibge.mvw_censo2010_info_Ysearch(y10);

-- !! FALTA empacotar tudo em 1km para poder buscar na grade 1km. Na de 200m não busca, só 1km pra cima.

-----

CREATE FUNCTION grid_ibge.search_xy10(p_x10 int, p_y10 int, p_level smallint) RETURNS bigint AS $f$
 SELECT grid_ibge.coordinate_encode10(t1x.x10, t1y.y10, p_level)
 FROM (
  SELECT x10 FROM (
    (
      SELECT x10
      FROM grid_ibge.mvw_censo2010_info_Xsearch
      WHERE level=p_level AND x10 >= p_x10
      ORDER BY x10 LIMIT 1
    )  UNION ALL (
      SELECT x10
      FROM grid_ibge.mvw_censo2010_info_Xsearch
      WHERE level=p_level AND x10 < p_x10
      ORDER BY x10 DESC LIMIT 1
    )
  ) t0x
  ORDER BY abs(p_x10-x10) LIMIT 1
) t1x, (
  SELECT y10 FROM (
    (
      SELECT y10
      FROM grid_ibge.mvw_censo2010_info_Ysearch
      WHERE level=p_level AND y10 >= p_y10
      ORDER BY y10 LIMIT 1
    )  UNION ALL (
      SELECT y10
      FROM grid_ibge.mvw_censo2010_info_Ysearch
      WHERE level=p_level AND y10 < p_y10
      ORDER BY y10 DESC LIMIT 1
    )
  ) t0y
  ORDER BY abs(p_y10-y10) LIMIT 1
) t1y
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION grid_ibge.search_cell(p_x real, p_y real, p_level smallint) RETURNS bigint AS $wrap$
  SELECT grid_ibge.search_xy10( round(p_x*10.0)::int, round(p_y*10.0)::int, p_level );
$wrap$ LANGUAGE SQL IMMUTABLE;

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- Reproduzindo a grade original a partir da compacta:

CREATE or replace FUNCTION grid_ibge.xy10_to_quadrante(
  x10 int, -- X*10, first coordinate of IBGE's Albers Projection
  y10 int -- Y*10, second coordinate of IBGE's Albers Projection
) RETURNS int AS $f$
DECLARE
  dx0 real; dy0 real; -- deltas
  i0 int; j0 int;   -- level0 coordinates
  ij int;           -- i0 and j0 as standard quadrant-indentifier.
BEGIN
  dx0 := x10::real/10.0 - 2800000.0;  dy0 := y10::real/10.0 - 7350000.0; -- encaixa na box dos quadrantes
  -- BUG! reduzir 15 e 23,  não são válidos aqui:
  i0 := floor( 15.341::real * dx0/7800000.0::real )::int;
  j0 := floor( 23.299::real * dy0/12350000.0::real )::int;
  ij := i0 + j0*10;
  IF ij NOT IN ( -- confere se entre os 54 quadrantes do território brasileiro
        4,13,14,15,23,24,25,26,27,33,34,35,36,37,39,42,43,44,45,46,47,50,51,52,53,54,55,56,
        57,58,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,80,81,82,83,84,85,92,93
      ) THEN
    RETURN NULL;
  END IF;
  RETURN ij;
END
$f$ LANGUAGE plpgsql IMMUTABLE;

CREATE or replace FUNCTION grid_ibge.xy_to_quadrante(
  x real, -- X, first coordinate of IBGE's Albers Projection
  y real  -- Y, second coordinate of IBGE's Albers Projection
) RETURNS int AS $wrap$
  SELECT grid_ibge.xy10_to_quadrante(round(x*10.0)::int, round(y*10.0)::int);
$wrap$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION grid_ibge.gid_to_quadrante(p_gid bigint) RETURNS int AS $wrap$
  SELECT grid_ibge.xy10_to_quadrante(gid[2],gid[3]) -- CASE WHEN gid[1]=0 THEN converteria direto?
  FROM ( SELECT grid_ibge.coordinate_decode10(p_gid) gid ) t
$wrap$ LANGUAGE SQL IMMUTABLE;

------

CREATE FUNCTION grid_ibge.draw_cell(
  cx real,  -- Center X
  cy real,  -- Center Y
  d int,   -- diâmetro do circulo inscrito
  p_translate boolean DEFAULT false, -- true para converter em LatLong (WGS84 sem projeção)
  p_srid int DEFAULT 952019          -- SRID da grade (default IBGE)
) RETURNS geometry AS $f$
SELECT CASE WHEN p_translate THEN ST_Transform(geom,4326) ELSE geom END
FROM (
  SELECT ST_GeomFromText( format(
    'POLYGON((%s %s,%s %s,%s %s,%s %s,%s %s))',
    cx-d,cy-d, cx-d,cy+d, cx+d,cy+d, cx+d,cy-d, cx-d,cy-d
  ), p_srid) AS geom
) t
$f$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION grid_ibge.draw_cell(real,real,int,boolean,int)
  IS 'Draws a square-cell centered on the requested real point, with requested radius (half side) and optional translation and SRID.'
;

CREATE FUNCTION grid_ibge.draw_cell(
  cx10 int,  -- Center X*10
  cy10 int,  -- Center Y*10
  d int,   -- diâmetro do circulo inscrito
  p_translate boolean DEFAULT false, -- true para converter em LatLong (WGS84 sem projeção)
  p_srid int DEFAULT 952019          -- SRID da grade (default IBGE)
) RETURNS geometry AS $wrap$
  SELECT grid_ibge.draw_cell(rcx, rcy, d, p_translate, p_srid)
  FROM ( SELECT cx10::real/10.0::real AS rcx, cy10::real/10.0::real AS rcy ) t
$wrap$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION grid_ibge.draw_cell(int,int,int,boolean,int)
  IS '(wrap for draw_cell of real coordinates) Draws a square-cell centered on the requested point gid*10, with requested radius (half side) and optional translation and SRID.'
;

CREATE FUNCTION grid_ibge.draw_cell(
  cXY10 int[], -- centro XY10 da célula codificado no ID
  d int,    -- diâmetro do circulo inscrito
  p_translate boolean DEFAULT false, -- true para converter em LatLong (WGS84 sem projeção)
  p_srid int DEFAULT 952019          -- SRID da grade (default IBGE)
) RETURNS geometry AS $wrap$
  SELECT grid_ibge.draw_cell( cXY10[1], cXY10[2], $2, $3, $4 )
$wrap$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION grid_ibge.draw_cell(int[],int,boolean,int)
  IS 'Wrap to draw_cell(int,int,*).'
;

CREATE FUNCTION grid_ibge.draw_cell(
  gid bigint, -- nível e centro XY10 da célula, codificados no geometricID
  p_translate boolean DEFAULT false, -- true para converter em LatLong (WGS84 sem projeção)
  p_srid int DEFAULT 952019          -- SRID da grade (default IBGE)
) RETURNS geometry AS $wrap$
  SELECT grid_ibge.draw_cell( xy[2], xy[3], grid_ibge.level_to_size(xy[1]), $2, $3 )
  FROM (SELECT grid_ibge.coordinate_decode10(gid) xy ) t
$wrap$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION grid_ibge.draw_cell(bigint,boolean,int)
  IS 'Wrap to draw_cell(int,int,*) using gid (embedding XY key) instead coordinates.'
;

---------------------------

--round( ST_x(ST_Transform(geom,952019)) + iif(is_200m,-100,-500) )::int x,
--round( ST_y(ST_Transform(geom,952019)) + iif(is_200m,+100,-500) )::int y

-- DROP VIEW grid_ibge.vw_original_ibge_rebuild;
CREATE VIEW grid_ibge.vw_original_ibge_rebuild AS
  SELECT gid,
         'idunico' AS id_unico, -- revisar
         'nome_1km' AS nome_1km,  --revisar
         grid_ibge.gid_to_quadrante(gid) quadrante,
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

/*
  SELECT '1KME'|| substr(gx::text,1,4) ||'N'|| substr(gy::text,1,4) AS nome_1km,
         'ID_'|| LPAD(ibge_prefix::text, 2, '0') AS quadrante,
         pop - fem AS masc,
         *,
         ibge_grid_cell(gx,gy,500,true) AS boxgeom
  FROM (
    SELECT *, ROUND(pop*pop_fem_perc::real/100.0)::int AS fem
    FROM grid_ibge.censo2010_info
  ) t
;

DROP VIEW IF EXISTS vwid45_grade_ibge_rebuild;
CREATE or replace VIEW vwid45_grade_ibge_rebuild AS
  SELECT * FROM vw_grade_ibge_rebuild WHERE ibge_prefix=45
;
*/

-----------------------------

--CREATE MATERIALIZED VIEW grid_ibge.kx_censo2010_geomcell AS -- gid, quadrante, geom.
--CREATE UNIQUE INDEX grid_ibge_kx_censo2010_geomcell
--  ON grid_ibge.kx_censo2010_geomcell (gid);
--CREATE MATERIALIZED VIEW grid_ibge.kx_censo2010_geomcenter AS -- gid, quadrante, geom.
--CREATE UNIQUE INDEX grid_ibge_kx_censo2010_geomcenter
--  ON grid_ibge.kx_censo2010_geomcenter (gid);


-----
-- CHECK BY NAME: WHERE NOT( substr(nome_1km,5,4)=substr(gx::text,1,4) AND substr(nome_1km,10,4)=substr(gy::text,1,4) );
