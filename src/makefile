##
## Grade Estatística IBGE, downloads e construção da sua Representação Compacta
##

pg_uri=postgres://postgres@localhost
pg_db=ibge

info:
	@echo "------------"
	@echo "Builds the Compact IBGE's Grade Estatística do Censo de 2010"
	@echo "------------"
	@echo "Builds database '$(pg_db)' with psql, change with pg_db=DatabaseName"
	@echo "Possible targets for this git package:"
	@echo " * all1: build all by alternative 1, downloading original grid"
	@echo " * all2: build all by alternative 2, from zip file"
	@echo " * sql_prepare: build and prepare database with pubLib"
	@echo " * grid_orig_get: download and build the original Grade IBGE on database"
	@echo " * grid_alt1_fromOrig: builds by alternative 1, from original, the Compact IBGE grid"
	@echo " * grid_alt2_fromZip: builds, by alternative 2, from Zip, the Compact IBGE grid"
	@echo "Optional targets for alternative 1:"
	@echo " * grid_alt1_checksums: create TXT files of checksums, from IBGE downloads"
	@echo " * grid_alt1_toZip: generates the compact Zip after build from new original version"
	@echo " * grid_alt1_clean: remove all IBGE tables and files"
	@echo " * validate: validates dtapackage"
	@echo " * grid_toGeoJSON: save GeoJSON file for level1"


## Abstract targets:

all1: sql_prepare grid_orig_get grid_alt1_fromOrig grid_homolog

all2: sql_prepare grid_alt2_fromZip

grid_alt1_clean: grid_alt1_clean_sql grid_alt1_clean_files

## Concrete builder targets:

sql_prepare:
	psql $(pg_uri) -c "CREATE DATABASE $(pg_db)"
	psql $(pg_uri)/$(pg_db) < step2/pubLib02-aggregate.sql
	psql $(pg_uri)/$(pg_db) < step2/pubLib03-admin.sql
	psql $(pg_uri)/$(pg_db) < step2/pubLib03-json.sql
	psql $(pg_uri)/$(pg_db) < step2/pubLib05-postGis.sql
	psql $(pg_uri)/$(pg_db) < step2/pubLib06-geoJSON.sql

grid_orig_get:
	@echo " (cuidado se a base não for $(pg_db)=IBGE, editar step3)"
	sh step1_download_IBGE.sh
	sh step3_build_IBGE.sh

grid_alt1_fromOrig:
	psql $(pg_uri)/$(pg_db) < step4_prepareGridLibs.sql
	psql $(pg_uri)/$(pg_db) < step5opt1_fromOriginal.sql
	psql $(pg_uri)/$(pg_db) < step6_asserts.sql

grid_alt2_fromZip: ../data/grid_ibge_censo2010_info.zip
	@echo "recuperando dados do git no PostgreSQL"
	psql $(pg_uri)/$(pg_db) < step4_prepareGridLibs.sql
	unzip -d /tmp  ../data/grid_ibge_censo2010_info.zip
	psql $(pg_uri)/$(pg_db) < step5opt2_fromCsv.sql
	rm -f /tmp/grid_ibge_censo2010_info.csv
	psql $(pg_uri)/$(pg_db) < step6_asserts.sql

## Concrete optional targets:
grid_alt1_checksums:
	@echo "Calculating checksums of original file"
	cd /tmp/sandbox/ibge_grade; md5sum grade_id*.zip > /tmp/sandbox/md5sum.txt
	cd /tmp/sandbox/ibge_grade; sha256sum grade_id*.zip > /tmp/sandbox/sha256sum.txt
	@echo "Use diff to compare with git checks"

grid_alt1_toZip:
	@echo "-- creating CSV and ZIP of new grid:"
	psql $(pg_uri)/$(pg_db) -c "CREATE extension IF NOT EXISTS adminpack"
	psql $(pg_uri)/$(pg_db) -c "SELECT pg_catalog.pg_file_unlink('/tmp/grid_ibge_censo2010_info.csv') AS rm_csv_file"
	psql $(pg_uri)/$(pg_db) -c "COPY (SELECT * FROM grid_ibge.censo2010_info ORDER BY gid&7, gid) TO '/tmp/grid_ibge_censo2010_info.csv' CSV HEADER"
	rm -f /tmp/grid_ibge_censo2010_info.zip
	zip -j /tmp/grid_ibge_censo2010_info.zip /tmp/grid_ibge_censo2010_info.csv
	@echo "Saved zip at /tmp"

validate:
	frictionless validate ../datapackage.yaml

grid_toGeoJSON:
	@echo "-- ASSERTs and GeoJSON generation:"
	psql $(pg_uri)/$(pg_db) < step6_asserts.sql
	@echo "GeoJSON 500KM and 100KM grids:"
	psql $(pg_uri)/$(pg_db) -c "SELECT pg_catalog.pg_file_unlink('/tmp/grid_ibge500km.geojson') AS rm_csv_file100km"
	psql $(pg_uri)/$(pg_db) -c "SELECT pg_catalog.pg_file_unlink('/tmp/grid_ibge100km.geojson') AS rm_csv_file500km"
	psql $(pg_uri)/$(pg_db) -c "SELECT * FROM vw_write_grid_ibge500km"
	psql $(pg_uri)/$(pg_db) -c "SELECT * FROM vw_write_grid_ibge100km"

grid_homolog: ../data/step7a_homolog.txt
	@echo "Reproduzindo os testes de homologação contra IBGE original (pode demorar)"
	cp ../data/ptCtrl.csv /tmp
	psql $(pg_uri)/$(pg_db) < step7a_homologLite.sql > /tmp/br_ibge_step7a_homolog.txt
	@echo " ... Conferindo por diff se bate com a última versão postada:"
	diff ../data/step7a_homolog.txt /tmp/br_ibge_step7a_homolog.txt

## Concrete cleaner targets:

grid_alt1_clean_sql:
	@echo "Drops the original grid tables, remaining only the compact one"
	psql $(pg_uri)/$(pg_db) < step6_dropOldIBGE.sql

grid_alt1_clean_files:
	@echo "Delete the original grid shapefiles"
	rm -r /tmp/sandbox/ibge_grade/
