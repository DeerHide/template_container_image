ARG UBUNTU_VERSION=22.04

FROM docker.io/library/ubuntu:$UBUNTU_VERSION as base

ARG APP_UID=1000
ARG APP_HOME=/home/appuser

# Setup the non-root user
RUN userdel --remove ubuntu \
    && useradd \
      --no-log-init \
      --uid $APP_UID \
      --home-dir ${APP_HOME} \
      --create-home \
      --user-group \
      appuser && \
    chown -R appuser:appuser ${APP_HOME}

# Update and upgrade the system
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get autoremove -y \
    && apt-get autoclean -y

FROM base as runtime

USER ${APP_UID}
WORKDIR ${APP_HOME}

CMD ["/bin/bash -c 'while true; do sleep 1; done'"]
