# Timescale Guide

## Introduction

TimescaleDB is a time-series database built on top of PostgreSQL. It is engineered up from PostgreSQL, providing full
SQL support and performance optimizations for time-series data.

### HyperTable

Hypertable is a logical table structure in TimescaleDB that is partitioned by time into smaller tables called chunks.

### Chunk

Each chunk is a table that is partitioned by time, and optionally, by additional space dimensions. In a distributed TimescaleDB setup, chunks can be distributed across multiple nodes.

### Compression

Compression in TimescaleDB is a feature designed to reduce storage space and improve query performance by compressing historical data in Hypertables. and it's applied at the chunk level. Details provided below.

- Benefits
  - **Storage Savings**: Compression significantly reduces the amount of disk space used by historical data, making it cost-effective for long-term data retention.
  - **Improved Query Performance**: Compressed data often requires fewer I/O operations, leading to faster query execution times, especially for queries involving large volumes of historical data.
  - **Cost Efficiency**: Reduced storage requirements lead to lower storage costs, particularly in cloud environments where storage costs can be significant.

- Strategy
  - Compression Algorithms: Different column types can use different compression algorithms. For example, numerical and timestamp columns might use combination of few algorithms(delta encoding, simple 8-b...etc), while text columns might use dictionary encoding.
  - Automatic and Manual Compression: Compression can be triggered manually for specific chunks or automated using policies that define when data should be compressed.

<br>

## Installation

### Pre-requisites

- Docker
- Docker-compose
- dockerfile (if you need more than Timescale extensions)

```dockerfile
FROM timescale/timescaledb:latest-pg16

RUN apk add postgis && \
    cp /usr/share/postgresql16/extension/* /usr/local/share/postgresql/extension/ && \
    cp /usr/lib/postgresql16/postgis* /usr/local/lib/postgresql/ && \
    cp -r /usr/lib/postgresql16/bitcode/* /usr/local/lib/postgresql/bitcode/

EXPOSE 5432
```

- init.sql

```sql
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE DATABASE rental;
```

- docker-compose.yml

```yaml
services:
  timescaledb:
    build:
      context: .
      dockerfile: timescaledb.dockerfile
    container_name: timescaledb
    environment:
      - POSTGRES_PASSWORD=123456
    ports:
      - "5433:5432"
    volumes:
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql
      - pgdata_v16:/var/lib/postgresql/data
    networks:
      - timescaledb
    restart: always

volumes:
  pgdata_v16:

networks:
  timescaledb:
    driver: bridge
```

### Hypertable creation

- create_hypertable()

  - Required arguments

    - table_name: The name of the table to convert to a hypertable.
    - dimension: Dimension builder for the column to partition on.

  - Optional arguments

    - create_default_indexes: Whether to create default indexes on time/partitioning columns. Default is TRUE.
    - if_not_exists: Check if the hypertable already exists before creation. If hypertable already exists will raise
      error. Default is FALSE.
    - migrate_data: Migrate data from the table to the hypertable. If table isn't empty will raise error. Default is
      FALSE.

  - Returns:

    - hypertable_id: ID of the hypertable in TimescaleDB.
    - created: TRUE if the hypertable was created, FALSE if it already existed.

  - Example
    - Older interface
      ```sql
      SELECT create_hypertable('@normal_table_name',
                             '@time_column_name',
                             chunk_time_interval => INTERVAL '1 month',
                             if_not_exists => TRUE,
                             migrate_data => TRUE
           );
      ```
    - Latest interface
      ```sql
      SELECT create_hypertable('@normal_table_name',
                             by_range('@time_column_name',INTERVAL '1 month'),
                             if_not_exists => TRUE,
                             migrate_data => TRUE
           );
      ```

### Compression

- Alter table (Compression)
  - Required argument
    - timescaledb.compress
  - Optional arguments
    - timescaledb.compress_orderby
    - timescaledb.compress_segmentby
    - timescaledb.compress_chunk_time_interval

  ```sql
    ALTER TABLE <table_name> SET (timescaledb.compress,
      timescaledb.compress_orderby = '<@column_name> [ASC | DESC] [ NULLS { FIRST | LAST } ] [, ...]',
      timescaledb.compress_segmentby = '<@column_name> [, ...]',
      timescaledb.compress_chunk_time_interval= INTERVAL '@time'
    );
  ```

- Enable compression policy 
  - Required arguments
    - hypertable_name
    - compress_after
  - Optional augments
    - schedule_interval: INTERVAL
    - initial_start: TIMESTAMPTZ. Time the policy is first run.
    - timezone
    - if_not_exists
    - compress_created_before: INTERVAL

  ```sql
    SELECT add_compression_policy('@table_name', INTERVAL '@time'); -- Enable compression policy
  ```

- Manual Compression
  - Required argument
    - chunk_name
  - Optional argument
    - if_not_compressed
  
  ```sql
    SELECT compress_chunk('@chunk_name', if_not_compressed => TRUE); -- Compress single chunk

    SELECT compress_chunk(i, if_not_compressed => TRUE)     -- Compress multiple chunks in single command
      FROM show_chunks('@table_name', older_than := INTERVAL '@time') i;
  ```

- Examples
  - Enable compression policy
    ```sql
      SELECT show_chunks('@table_name'); -- Display chunks.

      ALTER TABLE <table_name> SET (timescaledb.compress,
        timescaledb.compress_orderby = '<@column_name> [ASC | DESC] [ NULLS { FIRST | LAST } ] [, ...]',
        timescaledb.compress_segmentby = '<@column_name> [, ...]',
        timescaledb.compress_chunk_time_interval= INTERVAL '@time'
      );


      SELECT add_compression_policy('table_name', INTERVAL '45 days'); -- Enable compression policy

      SELECT * FROM chunk_compression_stats('table_name');  -- Display chunks after compression
    ```

  - Manual Compression
    ```sql
      SELECT show_chunks('@table_name', older_than => INTERVAL '@time'); -- Display chunks.

      SELECT compress_chunk('@chunk_name', if_not_compressed => TRUE); -- Compress single chunk

      SELECT compress_chunk(i, if_not_compressed => TRUE)     -- Compress chunks in single command
        FROM show_chunks('@table_name',
                          older_than := INTERVAL '@time'
      ) i;

      SELECT * FROM chunk_compression_stats('@table_name');  -- Display chunks after compression
    ```


### Note

- Constraint of the column to partition:
  - type in timestamp or timestamptz,
  - included as unique key,
  - defined as NOT NULL,
  - cannot be a reference for foreign key from other table,

- Traditional table cannot have a foreign key pointing to a hypertable.

## Troubleshooting

- `ERROR:  cannot create a unique index without the column "<COLUMN_NAME>" (used in partitioning)`

  - Solution: The column to partition on must be included as a unique key in the table. For existing tables, add the column to the primary key or unique index.

    ```text
      CREATE UNIQUE INDEX unique_id_created_at ON table_name(id, <COLUMN_NAME>);
    ```

    or

    ```text
      ALTER TABLE table_name
      DROP CONSTRAINT table_name_original_pkey;

      ALTER TABLE table_name
      ADD PRIMARY KEY (id, <COLUMN_NAME used IN partitioning>);
    ```

  - Reference: [Create a hypertable from a table with unique indexes](https://docs.timescale.com/use-timescale/latest/hypertables/hypertables-and-unique-indexes/)

- `ERROR: cannot have FOREIGN KEY constraints to hypertable`
  - Solution: Remove all foreign key constraints pointing to the table that will be converted to a hypertable. The sql used to query all foreign key constraints pointing to the table
    ```sql
      SELECT
        conname AS constraint_name,
        conrelid::regclass AS table,
        a.attname AS column_name
      FROM
        pg_constraint AS c
        JOIN pg_attribute AS a ON a.attnum = ANY (c.conkey)
      WHERE
        confrelid = 'table_that_will_be_convert_to_hypertable'::regclass;
    ```

## References

- Official documentation
  - [Hypertable](https://docs.timescale.com/use-timescale/latest/hypertables/)
    - [Create Hypertable](https://docs.timescale.com/api/latest/hypertable/create_hypertable/)
  - [Compression](https://docs.timescale.com/use-timescale/latest/compression/about-compression/)
    - [Compression Algorithm](https://docs.timescale.com/use-timescale/latest/compression/compression-methods/)
    - [Compression Policy](https://docs.timescale.com/use-timescale/latest/compression/compression-policy/)
    - [Manual Compression](https://docs.timescale.com/use-timescale/latest/compression/manual-compression/)
