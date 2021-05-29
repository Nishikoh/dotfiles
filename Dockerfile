FROM ubuntu:20.04
RUN apt-get update && \
    apt-get install build-essential curl file git vim ruby-full locales --no-install-recommends -y \
    && rm -rf /var/lib/apt/lists/* \

RUN localedef -i en_US -f UTF-8 en_US.UTF-8

RUN useradd -m -s /bin/bash linuxbrew && \
    echo 'linuxbrew ALL=(ALL) NOPASSWD:ALL' >>/etc/sudoers

USER linuxbrew
RUN /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# ADD init/ ./
USER root
ENV PATH="/home/linuxbrew/.linuxbrew/bin:${PATH}"
RUN cd && git clone https://github.com/Nishikoh/dotfile.git \
    && cd dofile/init && sh init.sh && sh link.sh