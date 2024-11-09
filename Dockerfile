FROM debian:stable-slim
RUN apt update && \
    apt install curl git xz-utils -y
COPY setup.sh setup.sh
# RUN bash setup.sh setup devbox
