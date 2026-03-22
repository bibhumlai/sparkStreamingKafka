from datetime import datetime

from airflow import DAG
from airflow.operators.bash import BashOperator


with DAG(
    dag_id="aiven_kafka_streaming_demo",
    start_date=datetime(2026, 3, 19),
    schedule=None,
    catchup=False,
    tags=["spark", "kafka", "aiven"],
) as dag:
    run_stream_once = BashOperator(
        task_id="run_stream_once",
        bash_command="""
        spark-submit \
          --master spark://spark-master:7077 \
          --packages org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.7 \
          /opt/project/apps/pyspark_kafka_stream.py \
          --mode once \
          --checkpoint /opt/project/output/checkpoints/airflow \
          --output /opt/project/output/airflow_output
        """,
    )

    load_into_postgres = BashOperator(
        task_id="load_into_postgres",
        bash_command="""
        python /opt/project/apps/load_stream_to_postgres.py \
          --input /opt/project/output/airflow_output
        """,
    )

    run_stream_once >> load_into_postgres
