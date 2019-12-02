from centos:7
ENV GRADLE_VERSION 6.0

RUN yum install -y java-1.8.0-openjdk java-1.8.0-openjdk-devel rpm-build python2 make which wget python-setuptools
RUN curl -s get.sdkman.io | bash
RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh \
&& sdk install gradle $GRADLE_VERSION"
ENV PATH="/root/.sdkman/candidates/gradle/$GRADLE_VERSION/bin/:${PATH}"
ADD linstor/linstor-server.sh /
ADD linstor/linstor-client.sh /
ADD linstor/python-linstor.sh /


VOLUME /RPMS
