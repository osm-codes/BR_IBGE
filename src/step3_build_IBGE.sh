## INGEST IBGE GRID
##
cd /tmp/sandbox/ibge_grade
ls *.zip | wc -l

cd /; ls /tmp/sandbox/ibge_grade/*.zip > /tmp/sandbox/ibge_grade/grades.txt; cd /tmp/sandbox/ibge_grade
while read in; do  unzip "$in"; done < grades.txt
cd /; ls /tmp/sandbox/ibge_grade/*.shp > /tmp/sandbox/ibge_grade/grades_shp.txt; cd /tmp/sandbox/ibge_grade
while read in; do  shp2pgsql -s 4326 "$in" | psql postgres://postgres@localhost/ibge -q ; done < grades_shp.txt


exit 0
