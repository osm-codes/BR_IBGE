echo "== Exemplo didático de manipulação dos dados brutos em terminal Linux =="
echo

unzip -d /tmp ../data/grid_ibge_censo2010_info.zip

echo "=== Primeiras linhas do CSV ===" > /tmp/t.txt
head /tmp/grid_ibge_censo2010_info.csv  >> /tmp/t.txt
echo "=== grep ===" >> /tmp/t.txt
grep 5756000087008006  /tmp/grid_ibge_censo2010_info.csv  >> /tmp/t.txt
echo "=== tot_lines ===" >> /tmp/t.txt
wc -l /tmp/grid_ibge_censo2010_info.csv  >> /tmp/t.txt
echo "=== L0 lines and L0 tot_pop ===" >> /tmp/t.txt
awk -F "," '/^[0-9]+0,/ {lines++; pop=pop+$2;} END{print lines, pop;}' /tmp/grid_ibge_censo2010_info.csv  >> /tmp/t.txt

echo "=== L1 lines and L1 tot_pop ===" >> /tmp/t.txt
awk -F "," '/^[0-9]+1,/ {lines++; pop=pop+$2;} END{print lines, pop;}' /tmp/grid_ibge_censo2010_info.csv  >> /tmp/t.txt

cat /tmp/t.txt

echo "== !Confira se tudo bem, diff vazio: =="
diff /tmp/t.txt ../data/assert_csv_samples.txt
