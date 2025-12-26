FROM mirror.gcr.io/debian:stable-slim
RUN apt update && \
    apt install curl git xz-utils -y
RUN apt install vim -y
RUN apt install unzip -y

COPY setup.sh setup.sh
# RUN bash setup.sh setup devbox
