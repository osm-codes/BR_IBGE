--
-- Grade IBGE em uma nova representação, ingestão a partir da grade original. Ver makefile para o processo completo.
--

-- -- -- -- -- -- -- -- -- -- --
-- Processo de ingestão do zip, ver make get_zcompact:

DELETE grid_ibge.censo2010_info;

COPY grid_ibge.censo2010_info FROM '/tmp/grid_ibge_censo2010_info.csv' CSV HEADER;
