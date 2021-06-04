# ClamAV plugin for bunkerized-nginx

### Compose example

```yaml
version: '3'
services:

  mywww:
    image: bunkerity/bunkerized-nginx
    ports:
      - 80:8080
    volumes:
      - ./web-files:/www:ro
      - ./plugins/clamav:/plugins/clamav:ro
    environment:
      - SERVER_NAME=www.website.com # replace with your domain
      - USE_CLIENT_CACHE=yes
      - USE_GZIP=yes
      - REMOTE_PHP=myphp
      - REMOTE_PHP_PATH=/app

  clamav-server:
    image: mkodockx/docker-clamav:alpine-idb-amd64

  clamav-rest-api:
    image: benzino77/clamav-rest-api
    depends_on:
      - clamav-server
    environment:
      - NODE_ENV=production
      - CLAMD_IP=clamav-server
      - APP_PORT=8080
      - APP_FORM_KEY=FILES

  myphp:
    image: php:fpm
    restart: always
    volumes:
      - ./web-files:/app
```
