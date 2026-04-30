ARG BASE_IMAGE=temurin-21-tools-deps-noble
FROM clojure:${BASE_IMAGE}

ARG USERNAME=ubuntu
ARG USER_UID=1000
ARG USER_GID=$USER_UID
    
# Create the user
RUN groupadd --gid $USER_GID $USERNAME || true \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME -s /bin/bash || true \
    #
    # [Optional] Add sudo support. Omit if you don't need to install software after connecting.
    && apt-get update \
    && apt-get install -y sudo \
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

RUN  apt-get update && \
     apt-get install -y lsb-release curl gnupg lsof
    
RUN  cd /tmp && \ 
     wget -qO install https://raw.githubusercontent.com/babashka/babashka/master/install &&  \
     chmod +x install && \
     ./install    

RUN bash -c 'curl -o- -L https://raw.githubusercontent.com/babashka/bbin/v0.2.4/bbin > /usr/local/bin/bbin' && \
    chmod +x /usr/local/bin/bbin     


RUN curl -s "https://ppa.jank-lang.org/KEY.gpg" | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/jank.gpg >/dev/null
RUN curl -s -o /etc/apt/sources.list.d/jank.list "https://ppa.jank-lang.org/jank.list"
RUN apt update
RUN apt install -y jank

# [Optional] Set the default user. Omit if you want to keep the default as root.
USER $USERNAME
SHELL ["/bin/bash", "-ec"]
ENTRYPOINT ["bash"]


# Prepare clojure tools
RUN clojure -Ttools list && \
clojure -Ttools install io.github.seancorfield/clj-new '{:git/tag "v1.2.404" :git/sha "d4a6508"}' :as clj-new && \
clojure -Ttools install-latest :lib io.github.seancorfield/deps-new :as new && \
clojure -Ttools list

RUN bbin install https://github.com/bhauman/clojure-mcp-light.git --tag v0.2.1 --as clj-nrepl-eval --main-opts '["-m" "clojure-mcp-light.nrepl-eval"]'

ENV PATH="$PATH:$HOME/.local/bin"
