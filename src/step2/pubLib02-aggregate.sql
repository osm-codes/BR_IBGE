
CREATE or replace FUNCTION  stragg_prefix(prefix text, s text[], sep text default ',') RETURNS text AS $f$
  SELECT string_agg(x,sep) FROM ( select prefix||(unnest(s)) ) t(x)
$f$ LANGUAGE SQL IMMUTABLE;
