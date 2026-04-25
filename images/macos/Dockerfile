FROM --platform=darwin/arm64 local/macos-base:latest

COPY payload/ComputerUseAgent.app /tmp/computer-use-install/ComputerUseAgent.app
COPY payload/bootstrap-agent /tmp/computer-use-install/bootstrap-agent
COPY launchd/io.github.jianliang00.computer-use.agent.plist /tmp/computer-use-install/io.github.jianliang00.computer-use.agent.plist
COPY launchd/io.github.jianliang00.computer-use.bootstrap.plist /tmp/computer-use-install/io.github.jianliang00.computer-use.bootstrap.plist
COPY scripts/install-computer-use.sh /tmp/computer-use-install/install-computer-use.sh
COPY scripts/configure-autologin.sh /tmp/computer-use-install/configure-autologin.sh

RUN BOOTSTRAP_LAUNCHD=0 /bin/bash /tmp/computer-use-install/install-computer-use.sh /tmp/computer-use-install
RUN /bin/bash /tmp/computer-use-install/configure-autologin.sh admin
RUN /bin/rm -rf /tmp/computer-use-install

CMD ["/usr/bin/tail", "-f", "/dev/null"]
