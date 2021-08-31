## Dados da Grade Compacta

Nesta pasta são mantidos os arquivos de dados do projeto. Os principais são descritos pelo [`datapackage.yaml`](../datapackage.yaml) na pasta-raiz.  O mais procurado é o _download_ da Grade Compacta: [grid_ibge_censo2010_info.zip](https://github.com/osm-codes/BR_IBGE/raw/main/data/grid_ibge_censo2010_info.zip

O arquivo [`ptCtrl.csv`](ptCtrl.csv) contém os "pontos de controle", que podem ser editados [nesta planilha colaborativa](https://docs.google.com/spreadsheets/d/1Z5Z98Q6D-mg4LGrURuayAEB7zkobJZlM2IkUxmXaBlg/edit#gid=0).

Na [seção "Distribuição" do README de apresentação do projeto](../README.md#distribuição-da-grade-compacta) maiores detalhes.

*Package* validado por `frictionless validate ../datapackage.yaml`.

------

Os formatos de arquivo e descritores de metadados seguem as recomendações  de   https://frictionlessdata.io/<br/>Foram utilizadas as [ferramentas do *framework* FrictionLessData](https://framework.frictionlessdata.io/docs/guides/quick-start).

<!-- Check also olds:
* https://create.frictionlessdata.io/
* https://www.youtube.com/watch?v=VrdPj28-L9g


-->


select distinct st_astect( st_centroid(geom)  ) from  grade_all_ids TABLESAMPLE BERNOULLI(0.01) limit 10
