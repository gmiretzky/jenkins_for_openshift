##############################################
# Stage 1 : Build go-init
##############################################
FROM openshift/golang-builder:rhel_8_golang_1.19 AS go-init-builder

WORKDIR  /go/src/github.com/openshift/jenkins
COPY . .
WORKDIR  /go/src/github.com/openshift/jenkins/go-init
RUN GO111MODULE=off go build . && cp go-init /usr/bin

##############################################
# Stage 2 : Build slave-base with go-init
##############################################
FROM openshift/ose-cli:v4.12
MAINTAINER OpenShift Developer Services <openshift-dev-services+jenkins@redhat.com>
COPY --from=go-init-builder /usr/bin/go-init /usr/bin/go-init

# Jenkins image for OpenShift
#
# This image provides a Jenkins server, primarily intended for integration with
# OpenShift v3.
#
# Volumes:
# * /var/jenkins_home
# Environment:
# * $JENKINS_PASSWORD - Password for the Jenkins 'admin' user.

MAINTAINER OpenShift Developer Services <openshift-dev-services+jenkins@redhat.com>

ENV JENKINS_VERSION=2 \
    HOME=/var/lib/jenkins \
    JENKINS_HOME=/var/lib/jenkins \
    JENKINS_UC=https://updates.jenkins.io \
    OPENSHIFT_JENKINS_IMAGE_VERSION=4.12 \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    INSTALL_JENKINS_VIA_RPMS=true
# openshift/ocp-build-data will change INSTALL_JENKINS_VIA_RPMS to true
# so that the osbs/brew builds will install via RPMs; when this runs
# in api.ci, it will employ the old centos style, download the plugins and
# redhat-stable core RPM for download


# Labels consumed by Red Hat build service

# 8080 for main web interface, 50000 for slave agents
EXPOSE 8080 50000

# for backward compatibility with pre-3.6 installs leveraging a PV, where rpm installs went to /usr/lib64/jenkins, we are
# establishing a symbolic link for that guy as well, so that existing plugins in JENKINS_HOME/plugins pointing to
# /usr/lib64/jenkins will subsequently get redirected to /usr/lib/jenkins; it is confirmed that the 3.7 jenkins RHEL images
# do *NOT* have a /usr/lib64/jenkins path
RUN ln -s /usr/lib/jenkins /usr/lib64/jenkins && \
    INSTALL_PKGS="dejavu-sans-fonts wget rsync gettext git git-lfs tar zip unzip openssl bzip2 java-11-openjdk java-11-openjdk-devel java-1.8.0-openjdk java-1.8.0-openjdk-devel jq glibc-locale-source xmlstarlet glibc-langpack-en" && \
    yum install -y $INSTALL_PKGS && \
    rpm -V  $INSTALL_PKGS && \
    yum update -y && \
    yum clean all  && \
    localedef -f UTF-8 -i en_US en_US.UTF-8 && \
    alternatives --family java-11 --install /usr/bin/java java /usr/lib/jvm/java-11-openjdk/bin/java 1  && \
    alternatives --set java java-11 && \
    alternatives --family javac-11 --install /usr/bin/javac javac /usr/lib/jvm/java-11-openjdk/bin/javac 1  && \
    alternatives --set javac javac-11 && \
    alternatives --family jar-11 --install /usr/bin/jar jar /usr/lib/jvm/java-11-openjdk/bin/jar 1  && \
    alternatives --set jar jar-11

COPY ./contrib/openshift /opt/openshift
COPY ./contrib/jenkins /usr/local/bin
ADD ./contrib/s2i /usr/libexec/s2i
ADD release.version /tmp/release.version

RUN /usr/local/bin/install-jenkins-core-plugins.sh /opt/openshift/bundle-plugins.txt && \
    rmdir /var/log/jenkins && \
    chmod -R 775 /etc/alternatives && \
    chmod -R 775 /var/lib/alternatives && \
    chmod -R 775 /usr/lib/jvm && \
    chmod 775 /usr/bin && \
    chmod 775 /usr/share/man/man1 && \
    mkdir -p /var/lib/origin && \
    chmod 775 /var/lib/origin && \
    chown -R 1001:0 /opt/openshift && \
    /usr/local/bin/fix-permissions /opt/openshift && \
    /usr/local/bin/fix-permissions /opt/openshift/configuration/init.groovy.d && \
    /usr/local/bin/fix-permissions /var/lib/jenkins && \
    /usr/local/bin/fix-permissions /var/log


VOLUME ["/var/lib/jenkins"]

USER 1001
ENTRYPOINT ["/usr/bin/go-init", "-main", "/usr/libexec/s2i/run"]

LABEL \
    io.k8s.description="Jenkins is a continuous integration server" \
    io.k8s.display-name="Jenkins 2" \
    io.openshift.tags="jenkins,jenkins2,ci" \
    io.openshift.expose-services="8080:http" \
    io.openshift.s2i.scripts-url="image:///usr/libexec/s2i" \
    com.redhat.component="openshift-jenkins-2-container" \
    name="openshift/ose-jenkins" \
    architecture="x86_64" \
    maintainer="openshift-dev-services+jenkins@redhat.com" \
    License="GPLv2+" \
    vendor="Red Hat" \
    io.openshift.maintainer.product="OpenShift Container Platform" \
    io.openshift.maintainer.component="Jenkins" \
    io.openshift.build.commit.id="a394440a8af6ad7f59d1ba7a82fe103f6bd08cca" \
    io.openshift.build.source-location="https://github.com/openshift/jenkins" \
    io.openshift.build.commit.url="https://github.com/openshift/jenkins/commit/a394440a8af6ad7f59d1ba7a82fe103f6bd08cca" \
    io.jenkins.version="2.440.3" \
    release="1716801209" \
    version="v4.12.0"
