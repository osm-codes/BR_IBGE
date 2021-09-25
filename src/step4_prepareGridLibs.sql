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
COMMENT ON COLUMN grid_ibge.censo2010_info.is_cache IS 'Indica que os dados não são originais da célula, são apenas totalizações em cache';

------

CREATE FUNCTION grid_ibge.level_to_size(level int)  RETURNS int AS $f$
  SELECT (array[500000, 100000, 50000, 10000, 5000, 1000, 200])[level+1]
  -- colnames array['nome_5km','nome_10km','nome_50km','nome_100km','nome_500km'];
$f$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION grid_ibge.level_to_size(int)
  IS 'Converts level number convention (IBGEs grid hierarchical level) into size of the cell side, in meters.'
;
CREATE FUNCTION grid_ibge.size_to_level(size int) RETURNS int AS $f$
  SELECT array_position( array[500000, 100000, 50000, 10000, 5000, 1000, 200], size) - 1
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION grid_ibge.prefix_to_level(prefix text) RETURNS int AS $f$
  SELECT array_position( array['500KM','100KM','50KM','10KM','5KM','1KM','200M'], prefix ) - 1;
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

CREATE FUNCTION grid_ibge.gid_to_xyLref(gid bigint) RETURNS int[] AS $f$
  -- X,Y,Level. curiosidade: seria mais rápido em X calcular gid/100000000000::bigint ?
  SELECT array[ substr(p,1,7)::int, substr(p,8,8)::int, (gid & 7::bigint)::int ]
  FROM ( SELECT gid::text p ) t
$f$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION grid_ibge.gid_to_xyLref
  IS 'Converts Bigint gid into reference-point XY Albers, and Level of the cell.'
;

CREATE or replace FUNCTION grid_ibge.gid_to_name(gid bigint) RETURNS text AS $f$
  SELECT grid_ibge.level_to_prefix((gid & 7::bigint)::int)
         ||'E'|| substr(p,1,digits)  -- full=substr(p,1,7)
         ||'N'|| substr( (substr(p,8,digits_y+1)::int)::text, 1, digits_y)   -- full=substr(p,8,8)
  FROM (
    SELECT p, digits,
           CASE WHEN substr(p,8,1)='1' THEN digits+1 ELSE digits END AS digits_y
    FROM ( SELECT gid::text p, CASE WHEN gid&7=6 THEN 5 ELSE 4 END AS digits ) t1
  ) t2
$f$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION grid_ibge.gid_to_name(bigint)
  IS 'Converts Bigint gid into original IBGE cell-name.'
;

CREATE FUNCTION grid_ibge.gid_to_xyLcenter(gid bigint) RETURNS int[] AS $f$
  SELECT CASE
    WHEN L=6 THEN array[ x_ref+halfside, y_ref-halfside, L ]
    ELSE          array[ x_ref+halfside, y_ref+halfside, L ]
    END
  FROM (
    SELECT p[1] as x_ref, p[2] as y_ref, p[3] as L,
           grid_ibge.level_to_size(p[3])/2::int as halfside
    FROM ( SELECT grid_ibge.gid_to_xyLref(gid) p ) t1
  ) t2
$f$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION grid_ibge.gid_to_xyLcenter
  IS 'Converts Bigint gid into center-XY Albers, and Level of the cell.'
;

CREATE FUNCTION grid_ibge.xylcenter_to_xyLref(x int, y int, nivel int) RETURNS int[] AS $f$
   -- CUIDADO retorna 4 itens, halfsize a mais que o xyL padrão
  -- descartar halfside, ninguém tá usando, só usaria em draw_cell mas usa draw from ref.
  SELECT CASE
    WHEN nivel=6 THEN array[ x-halfside, y+halfside, nivel, halfside ]
    ELSE              array[ x-halfside, y-halfside, nivel, halfside ]
    END
  FROM ( SELECT grid_ibge.level_to_size(nivel)/2::int as halfside ) t
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION grid_ibge.xyLref_to_gid(x int, y int, nivel int) RETURNS bigint AS $f$
  SELECT (
    rpad(tx, 7, '0') -- X
    || CASE WHEN substr(ty,1,1)='1' THEN rpad(ty,8,'0') ELSE '0'||rpad(ty,7,'0') END -- Y
    || L -- level
  )::bigint
  FROM ( SELECT x::text, y::text, nivel::text ) t(tx,ty,L)
$f$ LANGUAGE SQL IMMUTABLE;
CREATE FUNCTION grid_ibge.xyLref_to_gid(xyL int[]) RETURNS bigint AS $wrap$
  SELECT grid_ibge.xyLref_to_gid(xyL[1],xyL[2],xyL[3])
$wrap$ LANGUAGE SQL IMMUTABLE;

----
CREATE FUNCTION grid_ibge.xylcenter_to_gid(x int, y int, nivel int) RETURNS bigint AS $f$
  SELECT grid_ibge.xyLref_to_gid(p[1],p[2],p[3])
  FROM ( SELECT grid_ibge.xylcenter_to_xyLref(x,y,nivel) ) t(p)
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
CREATE FUNCTION grid_ibge.name_to_xyLcenter(name text) RETURNS int[] AS $f$
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
     END
   FROM (SELECT u*2) t(s)
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION grid_ibge.xyS_collapseTo_ijS(x int, y int, s int) RETURNS int[] AS $f$
  -- conferir se aritmética inteira trunca usando floor
  SELECT array[ (x-2800000)/s, (y-7350000)/s, s ] -- ex.s=500000
$f$ LANGUAGE SQL IMMUTABLE;
CREATE FUNCTION grid_ibge.xyS_collapseTo_ijS(xyS int[]) RETURNS int[] AS $wrap$
  SELECT grid_ibge.xys_collapseTo_ijs(xyS[1],xyS[2],xyS[3])
$wrap$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION grid_ibge.xyL_collapseTo_ijS(x int, y int, L int) RETURNS int[] AS $f$
  SELECT grid_ibge.xys_collapseTo_ijs(x,y, grid_ibge.level_to_size(L) )
$f$ LANGUAGE SQL IMMUTABLE;
CREATE FUNCTION grid_ibge.xyL_collapseTo_ijS(xyL int[]) RETURNS int[] AS $wrap$
  SELECT grid_ibge.xyL_collapseTo_ijS(xyL[1],xyL[2],xyL[3])
$wrap$ LANGUAGE SQL IMMUTABLE;

-- xyLref é a referência da célula, deixa de ser XY qualquer e passa a ser quantizado.

CREATE or replace FUNCTION grid_ibge.ijS_to_xySref(i int, j int, s int) RETURNS int[] AS $f$
  -- !para conversão Any usar ijS_to_xyScenter.
  SELECT CASE WHEN s=200 THEN array[xys[1], xys[2]+s, s] ELSE xys END
  FROM (
    SELECT array[ 2800000 + i*s, 7350000 + j*s, s ]
  ) t(xys)
$f$ LANGUAGE SQL IMMUTABLE;
CREATE FUNCTION grid_ibge.ijS_to_xySref(xys int[]) RETURNS int[] AS $wrap$
  SELECT grid_ibge.ijS_to_xySref(xys[1],xys[2],xys[3])
$wrap$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION grid_ibge.xyL_to_xySref(xyL int[]) RETURNS int[] AS $f$
  SELECT grid_ibge.ijS_to_xySref( grid_ibge.xyL_collapseTo_ijS(xyL) )
$f$ LANGUAGE SQL IMMUTABLE;
CREATE FUNCTION grid_ibge.xyL_to_xySref(x int, y int, L int DEFAULT 0) RETURNS int[] AS $wrap$
  SELECT grid_ibge.xyL_to_xySref(array[x,y,L])
$wrap$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION grid_ibge.xyL_to_xyLcenter(x int, y int, L int DEFAULT 0) RETURNS int[] AS $f$
  SELECT array[ xyL[1]+h, xyL[2]+h, xyL[3] ]
  FROM ( SELECT grid_ibge.xyL_to_xySref(x,y,L), L/2 ) t(xyL,h)
$f$ LANGUAGE SQL IMMUTABLE;

-- renomear usando _collapseTo_!!
CREATE FUNCTION grid_ibge.xy_to_quadrante(x int, y int) RETURNS int AS $f$
  SELECT 10*ij[2] + ij[1]
  FROM ( SELECT grid_ibge.xyS_collapseTo_ijS(x,y,500000) ) t(ij)
$f$ LANGUAGE SQL IMMUTABLE;
CREATE FUNCTION grid_ibge.xy_to_quadrante(xyd int[]) RETURNS int AS $wrap$
  SELECT grid_ibge.xy_to_quadrante(xyd[1],xyd[2]) -- drop xyd[3]
$wrap$ LANGUAGE SQL IMMUTABLE;
CREATE FUNCTION grid_ibge.xy_to_quadrante_text(x int, y int, prefix text DEFAULT 'ID_') RETURNS text AS $wrap$
  SELECT prefix||lpad(grid_ibge.xy_to_quadrante(x,y)::text,2,'0')
$wrap$ LANGUAGE SQL IMMUTABLE;
CREATE FUNCTION grid_ibge.xy_to_quadrante_text(xyd int[], prefix text DEFAULT 'ID_') RETURNS text AS $wrap$
  SELECT grid_ibge.xy_to_quadrante_text(xyd[1],xyd[2]) -- drop xyd[3]
$wrap$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION grid_ibge.quadrantes() RETURNS int[] AS $f$
  SELECT array[
      4,13,14,15,23,24,25,26,27,33,34,35,36,37,39,42,43,44,45,46,47,50,51,52,53,54,55,56,
      57,58,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,80,81,82,83,84,85,92,93
      ]
$f$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION grid_ibge.quadrantes IS 'List of official quadrants.';
CREATE FUNCTION grid_ibge.quadrantes_text(prefix text DEFAULT 'ID_') RETURNS text[] AS $wrap$
  SELECT array_agg( prefix||lpad(q::text,2,'0') )
  FROM unnest( grid_ibge.quadrantes() ) t(q)
$wrap$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION grid_ibge.xy_to_quadrante_valid(x int, y int) RETURNS int AS $f$
  SELECT ij
  FROM (SELECT grid_ibge.xy_to_quadrante(x,y)) t(ij)
  WHERE ij = ANY( grid_ibge.quadrantes() )
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION grid_ibge.gid_to_quadrante(gid bigint) RETURNS int AS $f$
  SELECT grid_ibge.xy_to_quadrante(xyL[1],xyL[2])
  FROM ( SELECT grid_ibge.gid_to_xyLcenter(gid) ) t(xyL)
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION grid_ibge.quadrante_to_gid(q int) RETURNS bigint AS $f$
  SELECT grid_ibge.xyLref_to_gid(p[1],p[2],0)
  FROM (SELECT grid_ibge.ijS_to_xySref(q-(q/10)*10, q/10, 500000)) t(p)
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION grid_ibge.gid_to_quadrante_text(gid bigint, prefix text DEFAULT 'ID_') RETURNS text AS $wrap$
  SELECT prefix||lpad(grid_ibge.gid_to_quadrante(gid)::text,2,'0')
$wrap$ LANGUAGE SQL IMMUTABLE;


------
---====== FIND CELL:

CREATE FUNCTION grid_ibge.xyLany_to_gid(x int, y int, L int) RETURNS bigint AS $f$
  SELECT grid_ibge.xyLref_to_gid( xy[1], xy[2], L )
  FROM (SELECT grid_ibge.ijS_to_xySref( grid_ibge.xyS_collapseTo_ijS(x,y,grid_ibge.level_to_size(L)) ) ) t(xy)
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION grid_ibge.xySany_to_gid(x int, y int, S int) RETURNS bigint AS $f$
  SELECT grid_ibge.xyLref_to_gid( xy[1], xy[2], grid_ibge.size_to_level(S) )
  FROM ( SELECT grid_ibge.ijS_to_xySref(grid_ibge.xyS_collapseTo_ijS(x,y,S)) ) t(xy)
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION grid_ibge.gid_to_gid(gid bigint, L int) RETURNS bigint AS $f$
  SELECT CASE WHEN gid & 7 = L THEN gid ELSE  grid_ibge.xyLany_to_gid(xyL[1],xyL[2],L) END
  FROM ( SELECT grid_ibge.gid_to_xyLcenter(gid) ) t(xyL)
$f$ LANGUAGE SQL IMMUTABLE;

CREATE or replace FUNCTION grid_ibge.gid_contains(big_gid bigint, small_gid bigint) RETURNS boolean AS $f$
  SELECT big_l < (small_gid & 7::bigint)::int
         AND big_gid = grid_ibge.xyLany_to_gid(xyl[1], xyl[2], big_l)
  FROM (SELECT (big_gid & 7::bigint)::int, grid_ibge.gid_to_xyLcenter(small_gid)) t(big_l,xyl)
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION grid_ibge.xyLany_to_name(x int, y int, L int) RETURNS text AS $f$
  SELECT grid_ibge.gid_to_name( grid_ibge.xyLany_to_gid(x,y,L) )
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION grid_ibge.xyLany_to_name(xyL int[], L int default NULL) RETURNS text AS $wrap$
  SELECT grid_ibge.xyLany_to_name(
           xyL[1], xyL[2], CASE WHEN L IS NULL THEN xyL[3] ELSE L END
  )
$wrap$ LANGUAGE SQL IMMUTABLE;

-- -- --
CREATE FUNCTION grid_ibge.ptgeomAny_to_gid( geom geometry(Point,4326),  L int ) RETURNS bigint AS $f$
  SELECT grid_ibge.xyLany_to_gid(ST_X(geom)::int, ST_Y(geom)::int, L)
  FROM ( SELECT ST_Transform(geom,952019) ) t(geom)
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION grid_ibge.latlonAny_to_gid(lat real, lon real, L int) RETURNS bigint AS $wrap$
  SELECT grid_ibge.ptgeomAny_to_gid( ST_SetSRID( ST_MakePoint(lon,lat),4326)  ,  L )
$wrap$ LANGUAGE SQL IMMUTABLE;
CREATE FUNCTION grid_ibge.latlonAny_to_gid(latlon real[], L int DEFAULT NULL) RETURNS bigint AS $wrap$
  SELECT grid_ibge.latlonAny_to_gid( latlon[1], latlon[2], COALESCE(L,5) )
$wrap$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION grid_ibge.geoURI_to_gid(geoURI text, L int DEFAULT 5) RETURNS bigint AS $f$
  SELECT grid_ibge.latlonAny_to_gid( p[1]::real, p[2]::real, CASE
    WHEN u IS NOT NULL THEN grid_ibge.size_to_level(grid_ibge.uncertain_to_size(u)) ELSE L END )
  FROM ( SELECT regexp_match(geoURI,'^geo:([+\-]?\d+\.?\d*),([+\-]?\d+\.?\d*)(?:;.+)?$') ) t1(p),
     LATERAL ( SELECT round((regexp_match(t1.p[3], 'u\s*=\s*(\d+\.?\d*)'))[1]::real)::int ) t2(u)
$f$ LANGUAGE SQL IMMUTABLE;

--------------
-- future change to other lib, grid_ghs:
CREATE FUNCTION grid_ibge.geoURI_to_geohash(geoURI text, digits int DEFAULT 9) RETURNS text AS $f$
  SELECT ST_GeoHash(ST_SetSRID(ST_MakePoint(p[2]::float,p[1]::float),4326), digits)
    -- digits: CASE WHEN u IS NOT NULL THEN uncertain_to_ghsdigits(u)) ELSE L END
  FROM ( SELECT regexp_match(geoURI,'^geo:([+\-]?\d+\.?\d*),([+\-]?\d+\.?\d*)(?:;.+)?$') ) t1(p)
     -- , LATERAL ( SELECT round((regexp_match(t1.p[3], 'u\s*=\s*(\d+\.?\d*)'))[1]::real)::int ) t2(u)
$f$ LANGUAGE SQL IMMUTABLE;


--=========
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

CREATE FUNCTION grid_ibge.draw_cell( -- by name
  cell_name text,
  p_translate boolean DEFAULT false, -- true para converter em LatLong (WGS84 sem projeção)
  p_srid int DEFAULT 952019          -- SRID da grade (default IBGE)
) RETURNS geometry AS $f$
  SELECT grid_ibge.draw_cell( xyL[1], xyL[2], round(grid_ibge.level_to_size(xyL[3])::real/2.0)::int, $2, $3 )
  FROM (SELECT grid_ibge.name_to_xyLcenter(cell_name) xyL ) t
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION grid_ibge.draw_cell( -- by GID.
  -- REVISAR!  Pode ser todo baseado em xyLref!
  gid bigint, -- nível e referência XY da célula, codificados no geometricID
  p_translate boolean DEFAULT false, -- true para converter em LatLong (WGS84 sem projeção)
  p_srid int DEFAULT 952019          -- SRID da grade (default IBGE)
) RETURNS geometry AS $wrap$
  SELECT grid_ibge.draw_cell( xyL[1], xyL[2], round(grid_ibge.level_to_size(xyL[3])::real/2.0)::int, $2, $3 )
  FROM (SELECT grid_ibge.gid_to_xyLcenter(gid) xyL ) t
$wrap$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION grid_ibge.draw_cell(bigint,boolean,int)
  IS 'Wrap to draw_cell(int,int,*) using gid (embedding XY key) instead coordinates.'
;

----==================
--  LIXOS? usar sempre ref. .. E ponto pode ser obtido de xyL diretamente.
CREATE FUNCTION grid_ibge.draw_cell_center( -- by name
  cell_name text,
  p_translate boolean DEFAULT false, -- true para converter em LatLong (WGS84 sem projeção)
  p_srid int DEFAULT 952019          -- SRID da grade (default IBGE)
) RETURNS geometry AS $f$
  SELECT CASE WHEN p_translate THEN ST_Transform(geom,4326) ELSE geom END
  FROM (
    SELECT ST_SetSRID( ST_MakePoint(xyL[1],xyL[2]),p_srid) geom
    FROM (SELECT grid_ibge.name_to_xyLcenter(cell_name) xyL ) t1
  ) t2
$f$ LANGUAGE SQL IMMUTABLE;

CREATE FUNCTION grid_ibge.draw_cell_center( -- by GID
  gid bigint,
  p_translate boolean DEFAULT false, -- true para converter em LatLong (WGS84 sem projeção)
  p_srid int DEFAULT 952019          -- SRID da grade (default IBGE)
) RETURNS geometry AS $f$
  SELECT CASE WHEN p_translate THEN ST_Transform(geom,4326) ELSE geom END
  FROM (
    SELECT ST_SetSRID( ST_MakePoint(xyL[1],xyL[2]),p_srid) geom
    FROM (SELECT grid_ibge.gid_to_xyLcenter(gid) xyL ) t1
  ) t2
$f$ LANGUAGE SQL IMMUTABLE;

---------------------------
-- drop FUNCTION grid_ibge.original_ibge_rebuild;
CREATE FUNCTION grid_ibge.original_ibge_rebuild(
  p_gid bigint,
  p_limit bigint DEFAULT 10 -- CUIDADO, com NULL leva horas ou dias!
) RETURNS TABLE (
    gid bigint,             id_unico text,
    nome_1km text,          nome_5km text,
    nome_10km text,         nome_50km text,
    nome_100km text,        nome_500km text,
    quadrante text,
    masc integer,           fem integer,
    pop integer,            dom_ocu integer,
    geom geometry
) AS $f$
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
         AND grid_ibge.gid_contains(p_gid,gid)
   LIMIT p_limit
  ) t
$f$ LANGUAGE SQL IMMUTABLE;
COMMENT ON FUNCTION grid_ibge.original_ibge_rebuild
  IS 'Original IBGE structure and content. A function like a parametrized VIEW, to void VIEW in QGIS and other scanners.'
;
-- exemplo. SELECT * FROM grid_ibge.original_ibge_rebuild(2800000103500001,500);
-- Evitar uso de quadrantes, mesmo com limit baixo pois gid_contains() é muito lenta. Exemplo perigoso:
--   SELECT * FROM grid_ibge.original_ibge_rebuild( grid_ibge.quadrante_to_gid(04), 20 );

------------------
------------------
--- API:

CREATE SCHEMA IF NOT EXISTS API;

CREATE FUNCTION api.resolver_geo_uri(geouri text) RETURNS JSONb AS $f$
 SELECT jsonb_build_object(
   'BR_IBGE_cell_L0_gid', cell_L0_gid,
   'BR_IBGE_cell_quadrante', grid_ibge.gid_to_quadrante_text(cell_L5_gid),
   'BR_IBGE_cell_L5_gid', cell_L5_gid,
   'BR_IBGE_cell_L0',grid_ibge.gid_to_name( cell_L0_gid ),
   'BR_IBGE_cell_L5',grid_ibge.gid_to_name( cell_L5_gid ),
   'geohash', grid_ibge.geoURI_to_geohash(geoURI, 9),
   'BR_IBGE_cell_L5_censo2010', to_jsonb((
     SELECT jsonb_build_object( 'pop',pop,  'dom_ocu',dom_ocu, 'pop_fem_perc',pop_fem_perc, 'pop_masc_perc',100-pop_fem_perc )
     FROM grid_ibge.censo2010_info
     WHERE gid=cell_L5_gid
    ))
   )
  FROM (
    SELECT cell_L5_gid, grid_ibge.gid_to_gid(cell_L5_gid,0) AS cell_L0_gid
    FROM ( SELECT grid_ibge.geoURI_to_gid(geouri,5) ) t1(cell_L5_gid)
  ) t2
$f$ LANGUAGE SQL IMMUTABLE;
