# If you want to save your container for future use, you use use the `docker
# commit` command
#   * docker commit <running container ID> puppet_agent_build
#   * docker run -it puppet_agent_build
#
# If using buildah, you probably want to build this as follows since various
# things might fail over time:
#   * buildah bud --layers=true -f <filename> .
#
# You can choose to build a specific version of puppet by setting the
# PUPPET_VERSION environment variable to a valid git reference in the
# puppet-agent repository.
#
# By default, the latest tag will be built.

# Build upstream Ruby
FROM centos:8
ENV container docker

WORKDIR /root

RUN yum -y install rpm-build yum-utils java-headless net-tools

# There's no rpmrebuild in EPEL yet
RUN rpm -i --nodigest --nofiledigest https://download-ib01.fedoraproject.org/pub/epel/7/x86_64/Packages/r/rpmrebuild-2.11-3.el7.noarch.rpm

RUN yum -y install https://yum.puppet.com/puppet6-release-el-8.noarch.rpm
RUN yum -y install puppet-agent
RUN yumdownloader puppetserver

RUN rpm -i --nodigest --nofiledigest puppetserver*.rpm

RUN dist=`rpm --eval '%{dist}'`; release=`rpm -q --qf="%{release}" puppetserver | cut -f1 -d'.'`; rpmrebuild --batch --release="${release}.SIMP1${dist}" puppetserver

RUN echo '############'; echo -n "Your file is at:"; find rpmbuild/RPMS -name "*.rpm"; echo '##########'

CMD /bin/bash
