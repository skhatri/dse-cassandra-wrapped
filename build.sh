docker rmi dse-server:latest || true
docker build --no-cache -t dse-server:latest .
