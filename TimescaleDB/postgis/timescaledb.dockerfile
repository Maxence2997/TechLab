FROM timescale/timescaledb:latest-pg16

RUN apk add postgis && \
    cp /usr/share/postgresql16/extension/* /usr/local/share/postgresql/extension/ && \
    cp /usr/lib/postgresql16/postgis* /usr/local/lib/postgresql/ && \
    cp -r /usr/lib/postgresql16/bitcode/* /usr/local/lib/postgresql/bitcode/

EXPOSE 5432