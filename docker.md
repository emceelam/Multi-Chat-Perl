# Running Docker

    sudo usermod -aG docker emceelam

    docker image build --tag multi_chat_perl:latest -f Dockerfile .

    docker container stop multi_chat_perl
      # stop the previous multi_chat_perl docker

    docker container run \
      --rm \
      --detach \
      --name multi_chat_perl \
      --publish 127.0.0.1:4021:4020 \
      multi_chat_perl:latest

    docker container ls

    # from one terminal
    telnet 127.0.0.1 4021

    # from another terminal
    telnet 127.0.0.1 4021

    # if you want to look inside
    docker exec --interactive --tty multi_chat_perl /bin/sh


# second container

    docker container run \
      --rm \
      --detach \
      --name multi_chat_perl-4021 \
      --publish 127.0.0.1:4021:4020 \
      multi_chat_perl:latest
