.PHONY: install data load-local build-local charts load-snowflake build-snowflake docs clean

DBT = cd dbt && DBT_PROFILES_DIR=. dbt

install:            ## Install Python dependencies
	pip install -r requirements-dev.txt

data:               ## Generate the synthetic lending dataset (5,000 borrowers)
	python data_generator/generate.py --borrowers 5000 --out data/raw

load-local: data    ## Load RAW tables into a local DuckDB file
	python loader/load.py --target duckdb

build-local: load-local  ## Run all dbt models and tests on DuckDB
	$(DBT) build --target dev

charts:             ## Re-render the README charts from the local marts
	python docs/make_charts.py

load-snowflake: data     ## PUT files to the stage and COPY INTO RAW
	python loader/load.py --target snowflake

build-snowflake:    ## Run all dbt models and tests on Snowflake
	$(DBT) build --target snowflake

docs:               ## Generate and serve dbt docs (lineage graph)
	$(DBT) docs generate --target dev && $(DBT) docs serve

clean:
	rm -rf data dbt/target dbt/logs
