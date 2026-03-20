import argparse
import json
import os
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import psycopg2
from psycopg2.extras import execute_batch


CARRIER_RE = re.compile(r"\b(?:USPS|DHL|COR|EXPRESS_POST)\b")
TRACKING_RE = re.compile(r"TR[A-Z]{2,3}\d+")
STATUS_RE = re.compile(r"(Delivered|En Route|Shipped|Returned_to_sender)\s*$")


@dataclass
class ParsedRecord:
    topic: str
    partition_id: int
    kafka_offset: int
    kafka_timestamp: str
    ingested_at: str
    tracking_id: str | None
    event_message: str | None
    carrier: str | None
    item_list: str | None
    destination_code: str | None
    shipment_status: str | None
    raw_message: str
    message_size_bytes: int | None


def build_args():
    parser = argparse.ArgumentParser(description="Load streamed Spark JSON output into Aiven Postgres.")
    parser.add_argument("--input", default="/opt/project/output/airflow_output")
    return parser.parse_args()


def env_or_fail(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise ValueError(f"Missing required environment variable: {name}")
    return value


def normalize_message(raw_message: str) -> str:
    return "".join(ch if 32 <= ord(ch) < 127 else "|" for ch in raw_message)


def sanitize_raw_message(raw_message: str) -> str:
    return raw_message.replace("\x00", "")


def clean_text(value: str | None) -> str | None:
    if value is None:
        return None
    cleaned = value.replace("|", " ").strip(" |*$")
    cleaned = re.sub(r"\s+", " ", cleaned).strip()
    return cleaned or None


def clean_items(value: str | None) -> str | None:
    cleaned = clean_text(value)
    if cleaned is None:
        return None
    cleaned = re.sub(r"^[A-Z](?=[A-Z][a-z])", "", cleaned)
    return cleaned.strip() or None


def parse_business_fields(raw_message: str) -> tuple[str | None, str | None, str | None, str | None, str | None]:
    printable = normalize_message(raw_message)
    tracking_match = TRACKING_RE.search(printable)
    carrier_match = CARRIER_RE.search(printable)
    status_match = STATUS_RE.search(printable)

    tracking_id = tracking_match.group(0) if tracking_match else None
    carrier = carrier_match.group(0) if carrier_match else None
    shipment_status = status_match.group(1) if status_match else None

    destination_code = None
    if status_match:
        prefix = printable[: status_match.start()]
        destination_codes = re.findall(r"([A-Z]{2,3})(?=[$| ]*$)", prefix)
        if destination_codes:
            destination_code = destination_codes[-1]

    event_message = None
    if tracking_match and carrier_match and tracking_match.end() <= carrier_match.start():
        event_message = clean_text(printable[tracking_match.end() : carrier_match.start()])
    elif tracking_match and carrier_match:
        embedded = printable[tracking_match.end() : carrier_match.start()]
        event_message = clean_text(embedded)

    item_list = None
    if carrier_match and status_match:
        item_end = status_match.start()
        if destination_code:
            dest_match = re.search(rf"([A-Z]{{2,3}})(?=[$| ]*{re.escape(shipment_status) if shipment_status else '$'})", printable[:status_match.end()])
            if dest_match:
                item_end = dest_match.start()
        item_list = clean_items(printable[carrier_match.end() : item_end])

    return tracking_id, event_message, carrier, item_list, destination_code, shipment_status


def iter_records(input_dir: Path) -> Iterable[ParsedRecord]:
    for path in sorted(input_dir.glob("part-*.json")):
        if path.stat().st_size == 0:
            continue
        with path.open("r", encoding="utf-8") as handle:
            for line in handle:
                row = json.loads(line)
                tracking_id, event_message, carrier, item_list, destination_code, shipment_status = parse_business_fields(
                    row["message_value"]
                )
                yield ParsedRecord(
                    topic=row["topic"],
                    partition_id=row["partition"],
                    kafka_offset=row["offset"],
                    kafka_timestamp=row["kafka_timestamp"],
                    ingested_at=row["ingested_at"],
                    tracking_id=tracking_id,
                    event_message=event_message,
                    carrier=carrier,
                    item_list=item_list,
                    destination_code=destination_code,
                    shipment_status=shipment_status,
                    raw_message=sanitize_raw_message(row["message_value"]),
                    message_size_bytes=row.get("message_size_bytes"),
                )


def connect():
    return psycopg2.connect(
        host=env_or_fail("AIVEN_PG_HOST"),
        port=env_or_fail("AIVEN_PG_PORT"),
        dbname=env_or_fail("AIVEN_PG_DATABASE"),
        user=env_or_fail("AIVEN_PG_USER"),
        password=env_or_fail("AIVEN_PG_PASSWORD"),
        sslmode="require",
        sslrootcert="/opt/project/secrets/aiven-ca.pem",
    )


def create_table(cur, table_name: str):
    cur.execute(
        f"""
        CREATE TABLE IF NOT EXISTS {table_name} (
            topic TEXT NOT NULL,
            partition_id INTEGER NOT NULL,
            kafka_offset BIGINT NOT NULL,
            kafka_timestamp TIMESTAMPTZ,
            ingested_at TIMESTAMPTZ,
            tracking_id TEXT,
            event_message TEXT,
            carrier TEXT,
            item_list TEXT,
            destination_code TEXT,
            shipment_status TEXT,
            raw_message TEXT NOT NULL,
            message_size_bytes INTEGER,
            loaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            PRIMARY KEY (topic, partition_id, kafka_offset)
        )
        """
    )


def insert_records(cur, table_name: str, records: list[ParsedRecord]):
    rows = [
        (
            r.topic,
            r.partition_id,
            r.kafka_offset,
            r.kafka_timestamp,
            r.ingested_at,
            r.tracking_id,
            r.event_message,
            r.carrier,
            r.item_list,
            r.destination_code,
            r.shipment_status,
            r.raw_message,
            r.message_size_bytes,
        )
        for r in records
    ]

    execute_batch(
        cur,
        f"""
        INSERT INTO {table_name} (
            topic,
            partition_id,
            kafka_offset,
            kafka_timestamp,
            ingested_at,
            tracking_id,
            event_message,
            carrier,
            item_list,
            destination_code,
            shipment_status,
            raw_message,
            message_size_bytes
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        ON CONFLICT (topic, partition_id, kafka_offset) DO UPDATE SET
            kafka_timestamp = EXCLUDED.kafka_timestamp,
            ingested_at = EXCLUDED.ingested_at,
            tracking_id = EXCLUDED.tracking_id,
            event_message = EXCLUDED.event_message,
            carrier = EXCLUDED.carrier,
            item_list = EXCLUDED.item_list,
            destination_code = EXCLUDED.destination_code,
            shipment_status = EXCLUDED.shipment_status,
            raw_message = EXCLUDED.raw_message,
            message_size_bytes = EXCLUDED.message_size_bytes,
            loaded_at = NOW()
        """,
        rows,
        page_size=200,
    )


def main():
    args = build_args()
    input_dir = Path(args.input)
    table_name = env_or_fail("AIVEN_PG_TABLE")
    records = list(iter_records(input_dir))
    if not records:
        print(f"No records found in {input_dir}")
        return

    with connect() as conn:
        with conn.cursor() as cur:
            create_table(cur, table_name)
            insert_records(cur, table_name, records)
        conn.commit()

    print(f"Loaded {len(records)} records into table '{table_name}'.")


if __name__ == "__main__":
    main()
