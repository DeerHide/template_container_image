ARG UBUNTU_VERSION=22.04

FROM docker.io/library/ubuntu:$UBUNTU_VERSION as base

ARG APP_UID=1000

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get dist-upgrade -y \
    && apt-get autoremove -y \
    && apt-get autoclean -y \
    && adduser \
      --disabled-password \
      --gecos '' \
      --uid $APP_UID \
      --home /home/appuser \
      appuser && \
    chown -R appuser:appuser /home/appuser && \
    cat /dev/null > /var/log/lastlog && \
    cat /dev/null > /var/log/faillog

FROM base as runtime

USER appuser
WORKDIR /home/appuser

CMD ["/bin/bash"]
