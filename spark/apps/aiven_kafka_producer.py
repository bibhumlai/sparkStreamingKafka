import argparse
import json
import os
import time
from datetime import datetime, timezone

from kafka import KafkaProducer


def build_args():
    parser = argparse.ArgumentParser(description="Publish sample JSON records to Aiven Kafka.")
    parser.add_argument("--count", type=int, default=10)
    parser.add_argument("--delay-seconds", type=float, default=1.0)
    return parser.parse_args()


def env_or_fail(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise ValueError(f"Missing required environment variable: {name}")
    return value


def build_producer() -> KafkaProducer:
    return KafkaProducer(
        bootstrap_servers=env_or_fail("AIVEN_KAFKA_BOOTSTRAP_SERVERS"),
        security_protocol="SASL_SSL",
        sasl_mechanism="PLAIN",
        sasl_plain_username=env_or_fail("AIVEN_KAFKA_USERNAME"),
        sasl_plain_password=env_or_fail("AIVEN_KAFKA_PASSWORD"),
        ssl_cafile="/opt/project/secrets/aiven-ca.pem",
        value_serializer=lambda value: json.dumps(value).encode("utf-8"),
        key_serializer=lambda key: key.encode("utf-8"),
    )


def main():
    args = build_args()
    topic = env_or_fail("AIVEN_KAFKA_TOPIC")
    producer = build_producer()

    for index in range(args.count):
        payload = {
            "event_id": index,
            "source": "local-docker-demo",
            "message": f"sample event {index}",
            "sent_at": datetime.now(timezone.utc).isoformat(),
        }
        key = f"event-{index}"
        producer.send(topic, key=key, value=payload)
        print(f"Sent message {index} to topic '{topic}'")
        time.sleep(args.delay_seconds)

    producer.flush()
    producer.close()


if __name__ == "__main__":
    main()
