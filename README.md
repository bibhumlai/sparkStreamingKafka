# Airflow + PySpark Streaming + Aiven Kafka

This project runs a local Docker stack with:

- Airflow webserver and scheduler
- PostgreSQL for Airflow metadata
- Spark standalone master and worker
- A sample PySpark Structured Streaming consumer for Aiven Kafka
- A small Kafka producer script for smoke testing

## Project layout

- `docker-compose.yml`: local stack definition
- `airflow/`: custom Airflow image and DAG
- `spark/apps/pyspark_kafka_stream.py`: Structured Streaming consumer
- `spark/apps/aiven_kafka_producer.py`: sample Kafka producer
- `secrets/`: TLS keypair and CA cert mounted into containers
- `output/`: streaming output and checkpoints

## Before you start

1. Update `AIVEN_KAFKA_TOPIC` in `.env` to a topic that exists in your Aiven Kafka service.
2. Keep the `secrets/` folder private. It contains the Kafka client key and certificates.

## Start the stack

```powershell
docker compose up --build airflow-init
docker compose up --build -d
```

Open these local endpoints:

- Airflow: http://localhost:8088
- Spark Master UI: http://localhost:9090
- Spark Worker UI: http://localhost:9091

Airflow login:

- Username: `admin`
- Password: `admin`

## Run the sample producer

This sends JSON messages into the configured Aiven topic.

```powershell
docker compose run --rm spark-client python /opt/project/apps/aiven_kafka_producer.py --count 10 --delay-seconds 1
```

## Run the streaming app manually

Use this for a long-running stream outside Airflow.

```powershell
docker compose run --rm spark-client spark-submit --master spark://spark-master:7077 --packages org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.7 /opt/project/apps/pyspark_kafka_stream.py --mode continuous --checkpoint /opt/project/output/checkpoints/manual --output /opt/project/output/manual_output
```

## Run from Airflow

1. Open Airflow at http://localhost:8088.
2. Turn on `aiven_kafka_streaming_demo`.
3. Trigger the DAG manually.

The Airflow task runs the Spark job in `once` mode, which drains currently available Kafka data and exits.

## Output

The streaming consumer writes JSON files under:

- `output/airflow_output`
- `output/manual_output`

Checkpoint directories are stored under `output/checkpoints`.

## Notes

- The sample consumer uses Kafka SSL/TLS with PEM files mounted from `secrets/`.
- If the topic is empty, the stream will stay idle in continuous mode.
- If you pasted real credentials into chat, rotate them after setup if you want to keep them private long-term.
