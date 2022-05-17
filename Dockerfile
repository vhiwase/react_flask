###########
# BUILDER #
###########

# 1. For build React app
FROM node:lts AS development
# Set working directory
WORKDIR /app
#
COPY client/package.json /app/package.json
COPY client/package-lock.json /app/package-lock.json
COPY client/postcss.config.js /app/postcss.config.js
COPY client/tailwind.config.js /app/tailwind.config.js
# Same as npm install
RUN npm ci
COPY client/ /app/
COPY deployment/ /app/deployment
ENV CI=true
ENV PORT=3000
CMD [ "npm", "start" ]
FROM development AS build
RUN npm run build

# This Dockerfile builds the server only.
###########
# BUILDER #
###########
# pull official base image
FROM python:3.10-slim-buster as builder
# set work directory
WORKDIR /usr/src/app/server
# set environment variables
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1
ENV FLASK_ENV production
# install system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends gcc
# lint
RUN pip install --upgrade pip
RUN pip install flake8==3.9.1
COPY ./server/ /usr/src/app/server/
RUN flake8 --exclude __init__.py --ignore=T001,T003,E402 ./ --max-line-length=250
# install python dependencies
COPY ./server/requirements/common.txt requirements/common.txt
COPY ./server/requirements/production.txt requirements/production.txt
RUN pip wheel --no-cache-dir --no-deps --wheel-dir /usr/src/app/server/wheels -r requirements/production.txt

#########
# FINAL #
#########
# pull official base image
FROM python:3.10-slim-buster
# create the app user
RUN addgroup --system app && adduser --system --group app
# create the appropriate directories
WORKDIR /app
COPY --from=build /app/build ./build
# install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends netcat
COPY --from=builder /usr/src/app/server/wheels /wheels
COPY --from=builder /usr/src/app/server/requirements/production.txt ./requirements/production.txt
RUN pip install --upgrade pip
RUN pip install --no-cache /wheels/*

RUN mkdir ./server
# copy source code
COPY ./server/app ./server/app
# COPY server/migrations ./server/migrations
COPY ./server/manage.py server/config.py ./server/

# chown all the files to the app user
RUN chown -R app:app ./server

# change to the app user
USER app

ENV SQLALCHEMY_DATABASE_URI mysql+pymysql://celebaltartan:CTartan12345@celebal-tartan-db.mysql.database.azure.com:3306/flaskproddb?ssl_ca=./app/database/DigiCertGlobalRootCA.crt.pem
ENV AZURE_REDIS_HOST "CelebalTartan.redis.cache.windows.net"
ENV AZURE_REDIS_PASSWORD "gKtowrl1NGs7PBbsga0iYBceuaqE4jYStAzCaMDgPa8="
ENV AZURE_REDIS_PORT="6380"

EXPOSE 3000
WORKDIR /app/server
ENTRYPOINT ["gunicorn", "--bind", "0.0.0.0:3000", "--access-logfile", "-", "--error-logfile", "-", "manage:app"]