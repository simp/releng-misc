# If you want to save your container for future use, you use use the `docker
# commit` command
#   * docker commit <running container ID> puppet_agent_build
#   * docker run -it puppet_agent_build
#
# If using buildah, you probably want to build this as follows since various
# things might fail over time:
#   * buildah bud --layers=true -f <filename> .
FROM centos:7
ENV container docker

## Fix issues with overlayfs
RUN yum clean all
RUN rm -f /var/lib/rpm/__db*
RUN yum clean all
RUN yum install -y yum-plugin-ovl || :
RUN yum install -y yum-utils

RUN yum install -y selinux-policy-targeted selinux-policy-devel policycoreutils policycoreutils-python

## Install necessary packages
RUN yum-config-manager --enable extras
RUN yum install -y epel-release
RUN yum install -y openssl util-linux rpm-build augeas-devel git gnupg2 libicu-devel libxml2 libxml2-devel libxslt libxslt-devel rpmdevtools which ruby-devel rpm-devel rpm-sign
RUN yum -y install fontconfig dejavu-sans-fonts dejavu-sans-mono-fonts dejavu-serif-fonts dejavu-fonts-common libjpeg-devel zlib-devel openssl-devel
RUN yum install -y libyaml-devel glibc-headers autoconf gcc gcc-c++ glibc-devel readline-devel libffi-devel automake libtool bison sqlite-devel

RUN yum install -y cmake

## Install helper packages
RUN yum install -y rubygems vim-enhanced jq

## Update all packages
RUN yum update -y

## Set up SCL Ruby
RUN yum install -y centos-release-scl
RUN yum-config-manager --enable rhel-server-rhscl-7-rpms
RUN yum install -y rh-ruby25 rh-ruby25-rubygem-bundler rh-ruby25-ruby-devel rh-ruby25-rubygem-rake
RUN echo '#!/bin/bash' | tee -a /etc/profile.d/scl_ruby.sh
RUN echo 'source scl_source enable rh-ruby25' | tee -a /etc/profile.d/scl_ruby.sh

## Check out a copy of the puppet components for building
RUN git clone https://github.com/puppetlabs/pl-build-tools-vanagon.git
RUN git clone https://github.com/puppetlabs/puppet-agent.git
RUN git clone https://github.com/puppetlabs/puppet-runtime.git

## Checkout latest tags
RUN cd pl-build-tools-vanagon && git describe --tags | xargs git checkout
RUN cd puppet-agent && git describe --tags | xargs git checkout
RUN cd puppet-runtime && git describe --tags | xargs git checkout

## Install the gems
RUN /bin/bash -l -c 'cd pl-build-tools-vanagon && bundle install'
RUN /bin/bash -l -c 'cd puppet-agent && bundle install'
RUN /bin/bash -l -c 'cd puppet-runtime && bundle install'

## Build vanagon tools
RUN /bin/bash -l -c 'cd pl-build-tools-vanagon && VANAGON_USE_MIRRORS=n bundle exec build -e local pl-gcc el-7-x86_64'
RUN /bin/bash -l -c 'cd pl-build-tools-vanagon && VANAGON_USE_MIRRORS=n bundle exec build -e local pl-cmake el-7-x86_64'
RUN /bin/bash -l -c 'cd pl-build-tools-vanagon && VANAGON_USE_MIRRORS=n bundle exec build -e local pl-ruby el-7-x86_64'
RUN cd pl-build-tools-vanagon && find output -name *.rpm | xargs yum -y install

## Build runtime
RUN /bin/bash -l -c 'cd puppet-runtime && bundle install'
RUN /bin/bash -l -c 'cd puppet-runtime && VANAGON_USE_MIRRORS=n bundle exec build -e local agent-runtime-6.4.x el-7-x86_64'
RUN /bin/bash -l -c 'cd puppet-runtime && VANAGON_USE_MIRRORS=n bundle exec build -e local agent-runtime-master el-7-x86_64'
RUN tar -czpvf /root/opt_puppetlabs_backup.tgz /opt/puppetlabs
RUN rm -rf /opt/puppetlabs

## Build agent
# Point to the local runtime build
RUN cd puppet-agent && sed -i 's|http://.*/artifacts/|file:///puppet-runtime/output|' configs/components/puppet-runtime.json

# Things only needed by the agent build that break the runtime builds
RUN /bin/bash -l -c 'cd pl-build-tools-vanagon && VANAGON_USE_MIRRORS=n bundle exec build -e local pl-openssl el-7-x86_64'
RUN /bin/bash -l -c 'cd pl-build-tools-vanagon && VANAGON_USE_MIRRORS=n bundle exec build -e local pl-boost el-7-x86_64'
RUN cd pl-build-tools-vanagon && find output -name *.rpm | xargs yum -y install
RUN /bin/bash -l -c 'cd pl-build-tools-vanagon && VANAGON_USE_MIRRORS=n bundle exec build -e local pl-curl el-7-x86_64'
RUN /bin/bash -l -c 'cd pl-build-tools-vanagon && VANAGON_USE_MIRRORS=n bundle exec build -e local pl-yaml-cpp el-7-x86_64'
RUN cd pl-build-tools-vanagon && find output -name *.rpm | xargs yum -y install

# Work around leatherman insanity
RUN echo /opt/pl-build-tools/lib | tee -a /etc/ld.so.conf && echo /opt/pl-build-tools/lib64 | tee -a /etc/ld.so.conf && ldconfig

# Work around the broken gemfile

RUN /bin/bash -l -c 'gem install rspec'
RUN /bin/bash -l -c 'cd puppet-agent && VANAGON_USE_MIRRORS=n bundle exec build -e local puppet-agent el-7-x86_64'

# Drop into a shell for building
CMD /bin/bash
