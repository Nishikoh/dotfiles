FROM ubuntu:20.04
RUN apt-get update && \
    apt-get install build-essential curl file git ruby-full locales --no-install-recommends -y \
    && rm -rf /var/lib/apt/lists/* \

RUN localedef -i en_US -f UTF-8 en_US.UTF-8

RUN useradd -m -s /bin/bash linuxbrew && \
    echo 'linuxbrew ALL=(ALL) NOPASSWD:ALL' >>/etc/sudoers

USER linuxbrew
ADD init/ ./
# ADD dofiles/ $HOME/dofiles/
RUN cd && git clone https://github.com/Nishikoh/dotfile.git \
    # && sh install.sh linux && sh link.sh

USER root
ENV PATH="/home/linuxbrew/.linuxbrew/bin:${PATH}"
