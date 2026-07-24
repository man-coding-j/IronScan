FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY Server ./Server
RUN pip install --no-cache-dir ./Server
COPY SharedContracts ./SharedContracts

EXPOSE 8000
CMD ["sh", "-c", "alembic -c Server/migrations/alembic.ini upgrade head && ironscan-seed && ironscan-debug-server"]
