import argparse
import os
from pathlib import Path

from pyspark.sql import SparkSession
from pyspark.sql.functions import col, current_timestamp, expr


def build_args():
    parser = argparse.ArgumentParser(description="Read from Aiven Kafka with PySpark Structured Streaming.")
    parser.add_argument("--mode", choices=["once", "continuous"], default="continuous")
    parser.add_argument("--checkpoint", default="/opt/project/output/checkpoints/streaming")
    parser.add_argument("--output", default="/opt/project/output/kafka_stream")
    return parser.parse_args()


def env_or_fail(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise ValueError(f"Missing required environment variable: {name}")
    return value


def build_spark() -> SparkSession:
    return (
        SparkSession.builder.appName("aiven-kafka-streaming-demo")
        .config("spark.sql.shuffle.partitions", "2")
        .getOrCreate()
    )


def read_secret(path: str) -> str:
    return Path(path).read_text(encoding="utf-8").strip()


def main():
    args = build_args()
    bootstrap_servers = env_or_fail("AIVEN_KAFKA_BOOTSTRAP_SERVERS")
    topic = env_or_fail("AIVEN_KAFKA_TOPIC")
    username = env_or_fail("AIVEN_KAFKA_USERNAME")
    password = env_or_fail("AIVEN_KAFKA_PASSWORD")
    starting_offsets = os.getenv("AIVEN_KAFKA_STARTING_OFFSETS", "latest")

    checkpoint_dir = Path(args.checkpoint)
    output_dir = Path(args.output)
    ca_cert = read_secret("/opt/project/secrets/aiven-ca.pem")
    checkpoint_dir.mkdir(parents=True, exist_ok=True)
    output_dir.mkdir(parents=True, exist_ok=True)

    spark = build_spark()
    spark.sparkContext.setLogLevel("WARN")

    source = (
        spark.readStream.format("kafka")
        .option("kafka.bootstrap.servers", bootstrap_servers)
        .option("subscribe", topic)
        .option("startingOffsets", starting_offsets)
        .option("failOnDataLoss", "false")
        .option("kafka.security.protocol", "SASL_SSL")
        .option("kafka.ssl.truststore.type", "PEM")
        .option("kafka.ssl.truststore.certificates", ca_cert)
        .option("kafka.sasl.mechanism", "PLAIN")
        .option(
            "kafka.sasl.jaas.config",
            f'org.apache.kafka.common.security.plain.PlainLoginModule required username="{username}" password="{password}";',
        )
        .load()
    )

    transformed = (
        source.selectExpr(
            "CAST(key AS STRING) AS message_key",
            "CAST(value AS STRING) AS message_value",
            "topic",
            "partition",
            "offset",
            "timestamp AS kafka_timestamp",
        )
        .withColumn("ingested_at", current_timestamp())
        .withColumn("message_size_bytes", expr("length(message_value)"))
        .select(
            "topic",
            "partition",
            "offset",
            "kafka_timestamp",
            "ingested_at",
            "message_key",
            "message_value",
            col("message_size_bytes"),
        )
    )

    writer = (
        transformed.writeStream.outputMode("append")
        .format("json")
        .option("path", str(output_dir))
        .option("checkpointLocation", str(checkpoint_dir))
    )

    if args.mode == "once":
        query = writer.trigger(availableNow=True).start()
    else:
        query = writer.start()

    print(f"Streaming from topic '{topic}' at '{bootstrap_servers}' in mode '{args.mode}'.")
    print(f"Output path: {output_dir}")
    print(f"Checkpoint path: {checkpoint_dir}")
    query.awaitTermination()


if __name__ == "__main__":
    main()
