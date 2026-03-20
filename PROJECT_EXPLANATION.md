# Project Explanation: Airflow + PySpark Streaming + Aiven Kafka + Aiven Postgres

This document explains how the project works, what each file does, how the data moves through the system, and why the code is written the way it is.

Project location:

- `D:\DE\Spark Streaming`

Main goal of this project:

- Run Airflow locally with Docker
- Run a PySpark Structured Streaming job locally
- Read logistics events from Aiven Kafka
- Save raw stream output as JSON files locally
- Transform the streamed data into a cleaner schema
- Load the transformed records into Aiven Postgres

## 1. High-Level Architecture

The project has four main parts:

1. Airflow
2. Spark
3. Aiven Kafka
4. Aiven Postgres

Flow of data:

1. Airflow triggers the Spark streaming script.
2. Spark reads Kafka messages from Aiven Kafka.
3. Spark writes the streamed records to local JSON output files.
4. A Python loader reads those JSON files.
5. The loader extracts business fields from the raw message payload.
6. The loader creates a Postgres table if it does not exist.
7. The loader inserts or updates rows in Aiven Postgres.

## 2. Folder Structure

Important files and folders:

- `docker-compose.yml`
- `.env`
- `airflow/`
- `airflow/Dockerfile`
- `airflow/requirements.txt`
- `airflow/dags/aiven_kafka_streaming.py`
- `spark/`
- `spark/Dockerfile`
- `spark/apps/pyspark_kafka_stream.py`
- `spark/apps/aiven_kafka_producer.py`
- `spark/apps/load_stream_to_postgres.py`
- `secrets/`
- `output/`

What each folder is for:

- `airflow/`: Airflow image build files and DAG definitions
- `spark/`: Spark client image and Python apps
- `secrets/`: CA certificate and other connection materials
- `output/`: Streamed JSON output and Spark checkpoints

## 3. docker-compose.yml

File:

- `docker-compose.yml`

This file defines all Docker services used in the project.

### 3.1 postgres service

Purpose:

- Stores Airflow metadata, such as DAG runs, task state, and logs metadata

Important settings:

- `POSTGRES_USER=airflow`
- `POSTGRES_PASSWORD=airflow`
- `POSTGRES_DB=airflow`

Why it is needed:

- Airflow needs a database backend
- SQLite is not suitable for this multi-service setup

### 3.2 spark-master service

Purpose:

- Runs Spark standalone master

Command:

- Starts `org.apache.spark.deploy.master.Master`

Ports:

- `7077`: Spark cluster port
- `9090`: Spark master UI mapped from container port 8080

Why `user: "0:0"` is set:

- On Windows-mounted folders, Spark sometimes fails to write output because of permissions
- Running as root avoids `Permission denied` errors when writing stream output

### 3.3 spark-worker service

Purpose:

- Runs a Spark standalone worker connected to the master

Command:

- Starts `org.apache.spark.deploy.worker.Worker`

Why it exists:

- The Spark streaming job needs executors to process tasks

### 3.4 spark-client service

Purpose:

- A general-purpose container where we can run `spark-submit` and helper scripts

Why it exists:

- Airflow triggers Spark jobs from this environment
- It also lets us run producer scripts or test commands manually

### 3.5 airflow-init service

Purpose:

- Initializes the Airflow metadata database
- Creates the admin user

Why it runs once:

- Airflow needs database migration before the webserver and scheduler can work

### 3.6 airflow-webserver service

Purpose:

- Runs the Airflow UI

Port:

- `8088` on your machine

Why it matters:

- You use this to trigger DAGs, inspect runs, and see task status

### 3.7 airflow-scheduler service

Purpose:

- Reads DAGs and schedules tasks

Why it matters:

- Without the scheduler, Airflow can show DAGs but won’t execute work properly

### 3.8 Shared mounts

These folders are mounted into services:

- `./airflow/dags`
- `./airflow/logs`
- `./spark/apps`
- `./output`
- `./secrets`

Why mounts are important:

- Code changes reflect inside containers
- Logs stay on disk
- Output files remain available after container restarts

## 4. .env

File:

- `.env`

This file stores environment variables used by Docker Compose and by the application code.

Important groups:

### 4.1 Kafka variables

- `AIVEN_KAFKA_BOOTSTRAP_SERVERS`
- `AIVEN_KAFKA_TOPIC`
- `AIVEN_KAFKA_STARTING_OFFSETS`
- `AIVEN_KAFKA_USERNAME`
- `AIVEN_KAFKA_PASSWORD`

These are used by:

- `pyspark_kafka_stream.py`
- `aiven_kafka_producer.py`

### 4.2 Airflow variables

- `AIRFLOW_UID`
- `AIRFLOW_ADMIN_USERNAME`
- `AIRFLOW_ADMIN_PASSWORD`
- `AIRFLOW_FERNET_KEY`
- `AIRFLOW_WEBSERVER_SECRET_KEY`

Why they matter:

- They define the local Airflow admin user
- They control encryption and session consistency inside Airflow

### 4.3 Postgres loader variables

- `AIVEN_PG_HOST`
- `AIVEN_PG_PORT`
- `AIVEN_PG_DATABASE`
- `AIVEN_PG_USER`
- `AIVEN_PG_PASSWORD`
- `AIVEN_PG_TABLE`

These are used by:

- `load_stream_to_postgres.py`

## 5. airflow/Dockerfile

File:

- `airflow/Dockerfile`

Base image:

- `apache/airflow:2.10.5-python3.11`

What it adds:

- Java runtime
- `procps`
- Python dependencies from `requirements.txt`

Why Java is installed:

- Spark needs Java
- Airflow runs `spark-submit` in this setup

## 6. airflow/requirements.txt

File:

- `airflow/requirements.txt`

Packages:

- `pyspark==3.5.7`
- `psycopg2-binary==2.9.10`

Why these are needed:

- `pyspark`: Airflow can execute the Spark submission command in a compatible environment
- `psycopg2-binary`: Allows the loader script to connect to Aiven Postgres

## 7. Airflow DAG: aiven_kafka_streaming.py

File:

- `airflow/dags/aiven_kafka_streaming.py`

This DAG contains the orchestration logic.

### 7.1 DAG definition

It creates a DAG named:

- `aiven_kafka_streaming_demo`

Properties:

- `schedule=None`
- `catchup=False`

Meaning:

- It does not run on a time schedule automatically
- You trigger it manually

### 7.2 Task: run_stream_once

Operator:

- `BashOperator`

Command:

- Runs `spark-submit`
- Connects to Spark master
- Includes Spark Kafka package
- Executes `pyspark_kafka_stream.py`
- Uses `--mode once`

Why `once` mode:

- It processes currently available Kafka data and exits
- That makes it easier to orchestrate in Airflow

### 7.3 Task: load_into_postgres

Operator:

- `BashOperator`

Command:

- Runs `load_stream_to_postgres.py`

What it does:

- Reads JSON output created by the streaming task
- Creates the target table if needed
- Loads rows into Aiven Postgres

### 7.4 Task dependency

The DAG uses:

- `run_stream_once >> load_into_postgres`

Meaning:

- The Postgres load only runs after streaming finishes successfully

## 8. spark/Dockerfile

File:

- `spark/Dockerfile`

Base image:

- `spark:3.5.7-java17-python3`

Extra package:

- `kafka-python`

Why it is needed:

- The producer helper script uses `KafkaProducer`

## 9. Spark App: pyspark_kafka_stream.py

File:

- `spark/apps/pyspark_kafka_stream.py`

This is the main streaming application.

### 9.1 Purpose

- Reads Kafka messages from Aiven Kafka
- Uses Spark Structured Streaming
- Writes stream output to JSON files

### 9.2 Argument parsing

It accepts:

- `--mode`
- `--checkpoint`
- `--output`

Why these options exist:

- `mode`: lets the app run in `once` or `continuous` mode
- `checkpoint`: stores streaming state
- `output`: controls where JSON files are written

### 9.3 env_or_fail

Function:

- `env_or_fail(name)`

Purpose:

- Ensures required environment variables are present

Why it is useful:

- Fails early with a clear error instead of producing confusing runtime behavior

### 9.4 read_secret

Function:

- `read_secret(path)`

Purpose:

- Reads CA certificate contents

Why it is used:

- Spark/Kafka SSL settings need the PEM content, not just the path, in this setup

### 9.5 build_spark

Function:

- Creates the Spark session

Important setting:

- `spark.sql.shuffle.partitions = 2`

Why:

- Keeps local processing lightweight

### 9.6 Kafka connection config

The stream reads Kafka using:

- `kafka.bootstrap.servers`
- `subscribe`
- `startingOffsets`
- `kafka.security.protocol`
- `kafka.sasl.mechanism`
- `kafka.sasl.jaas.config`
- `kafka.ssl.truststore.type`
- `kafka.ssl.truststore.certificates`

Why SASL is used:

- Your working Aiven Kafka listener uses username/password authentication

### 9.7 DataFrame transformation

The script converts Kafka fields into readable columns:

- `message_key`
- `message_value`
- `topic`
- `partition`
- `offset`
- `kafka_timestamp`
- `ingested_at`
- `message_size_bytes`

Why these fields are useful:

- Kafka metadata is needed for traceability
- `message_value` contains the business payload
- `message_size_bytes` helps with debugging payload size

### 9.8 Stream sink

The app writes data to:

- JSON files

Output mode:

- `append`

Why:

- Each incoming Kafka record becomes a new JSON row

### 9.9 availableNow trigger

If `--mode once` is used:

- `availableNow=True`

Meaning:

- Spark processes currently available messages and then stops

This makes it ideal for Airflow batch-style orchestration.

## 10. Producer Script: aiven_kafka_producer.py

File:

- `spark/apps/aiven_kafka_producer.py`

Purpose:

- Sends sample JSON events to Aiven Kafka

What it does:

- Builds a Kafka producer
- Uses `SASL_SSL`
- Uses Aiven username/password
- Sends simple JSON payloads

Why it exists:

- Useful for smoke testing the Kafka connection and stream

## 11. Loader Script: load_stream_to_postgres.py

File:

- `spark/apps/load_stream_to_postgres.py`

This script transforms raw output files into a final schema and loads them into Aiven Postgres.

### 11.1 What input it reads

It reads:

- JSON output files under `output/airflow_output`

Each row contains:

- Kafka metadata
- raw `message_value`

### 11.2 Final schema

The loader creates this business-friendly schema:

- `topic`
- `partition_id`
- `kafka_offset`
- `kafka_timestamp`
- `ingested_at`
- `tracking_id`
- `event_message`
- `carrier`
- `item_list`
- `destination_code`
- `shipment_status`
- `raw_message`
- `message_size_bytes`
- `loaded_at`

### 11.3 Regex patterns

The script uses patterns to detect:

- tracking ID
- carrier
- status

Examples:

- tracking IDs like `TRBEL38776`
- carriers like `DHL`, `USPS`, `COR`, `EXPRESS_POST`
- statuses like `Delivered`, `En Route`, `Shipped`

Why regex is used:

- The Kafka payload is not arriving as clean JSON fields
- We need to infer structure from a mixed string payload

### 11.4 normalize_message

Purpose:

- Replaces non-printable characters with `|`

Why:

- The raw Kafka payload contains binary-like characters
- Replacing them makes field extraction easier

### 11.5 sanitize_raw_message

Purpose:

- Removes NUL bytes (`\x00`)

Why:

- Postgres text columns cannot store NUL characters

### 11.6 parse_business_fields

Purpose:

- Derives business fields from the raw message string

It extracts:

- `tracking_id`
- `event_message`
- `carrier`
- `item_list`
- `destination_code`
- `shipment_status`

Why this is important:

- Raw stream output is not good for analytics
- This function converts it into a more useful relational schema

### 11.7 iter_records

Purpose:

- Reads all `part-*.json` files
- Skips empty files
- Yields parsed records one by one

Why it is written this way:

- It makes the loader tolerant of Spark output structure

### 11.8 connect

Purpose:

- Opens an SSL connection to Aiven Postgres

Uses:

- host
- port
- database
- username
- password
- CA certificate

### 11.9 create_table

Purpose:

- Creates the Postgres table if it does not already exist

Primary key:

- `(topic, partition_id, kafka_offset)`

Why this key is chosen:

- Kafka offset is unique within a topic partition
- It makes the load idempotent

### 11.10 insert_records

Purpose:

- Inserts rows in batches
- Uses `ON CONFLICT ... DO UPDATE`

Why:

- Re-running the loader should not create duplicates
- Existing rows get updated if needed

### 11.11 main

Purpose:

- Reads records
- Creates the table
- Loads the records
- Prints how many rows were inserted

## 12. secrets Folder

Folder:

- `secrets/`

Important file:

- `aiven-ca.pem`

Why it is needed:

- Used for TLS verification when connecting to Aiven Kafka and Aiven Postgres

Note:

- Earlier versions of this project also used client certificate/key files for Kafka
- The working Kafka connection now uses SASL with username/password instead

## 13. output Folder

Folder:

- `output/`

Subfolders:

- `output/airflow_output`
- `output/checkpoints/airflow`

### 13.1 airflow_output

Purpose:

- Stores JSON output files produced by the Spark stream

### 13.2 checkpoints

Purpose:

- Stores Spark checkpoint metadata

Why checkpoints matter:

- They allow Spark to track which Kafka offsets were processed

## 14. Why Some Earlier Errors Happened

This project went through several real-world integration issues while being built.

### 14.1 Invalid PEM keystore configs

Cause:

- Kafka client certificate config was not matching the actual Aiven listener setup

Resolution:

- Switched to the Aiven SASL listener with username/password

### 14.2 Invalid topic name

Cause:

- Topic name was copied with extra UI text

Resolution:

- Set the topic to `logistics_data_gen`

### 14.3 Permission denied writing Spark output

Cause:

- Spark worker could not write to Windows-mounted output paths

Resolution:

- Spark services were run as root inside Docker

### 14.4 Postgres NUL-byte insert failure

Cause:

- Raw Kafka payload contained `\x00`

Resolution:

- Sanitized `raw_message` before inserting into Postgres

## 15. Current Working State

What currently works:

- Docker stack starts
- Airflow UI runs locally
- Spark master and worker run locally
- Kafka stream can be read and written to output files
- Transformed data can be loaded into Aiven Postgres
- Table `logistics_stream_events` exists and contains loaded rows

Verified table:

- `logistics_stream_events`

Verified sample fields:

- tracking ID
- carrier
- destination code
- shipment status

## 16. How to Run It

### 16.1 Start the stack

```powershell
docker compose up --build -d
```

### 16.2 Open Airflow

```text
http://localhost:8088
```

### 16.3 Trigger the DAG

```powershell
docker compose exec airflow-webserver airflow dags trigger aiven_kafka_streaming_demo
```

### 16.4 View output files

```powershell
Get-ChildItem "D:\DE\Spark Streaming\output\airflow_output"
```

### 16.5 Query loaded Postgres data

```sql
SELECT *
FROM logistics_stream_events
ORDER BY kafka_offset DESC
LIMIT 20;
```

## 17. Suggested Next Improvements

If you want to make this more production-like, these would be the next good steps:

1. Move secrets out of `.env` and into Docker secrets or a secret manager
2. Separate the stream DAG and the load DAG for cleaner retries
3. Add stronger parsing rules for all message patterns
4. Save parsed items as arrays or normalized child tables
5. Add a dbt model on top of `logistics_stream_events`
6. Add data quality checks for null tracking IDs or invalid status values

## 18. Summary

This project is a local end-to-end streaming pipeline:

- Airflow orchestrates
- Spark consumes Kafka
- JSON files store raw stream results
- Python transforms the raw records
- Aiven Postgres stores the final relational output

The most important code paths are:

- `airflow/dags/aiven_kafka_streaming.py`
- `spark/apps/pyspark_kafka_stream.py`
- `spark/apps/load_stream_to_postgres.py`

Those three files together represent the orchestration layer, streaming layer, and loading layer.
