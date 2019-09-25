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
RUN yum install -y openssl util-linux rpm-build augeas-devel git gnupg2 libicu-devel libxml2 libxml2-devel libxslt libxslt-devel rpmdevtools which rpm-devel rpm-sign
RUN yum -y install fontconfig dejavu-sans-fonts dejavu-sans-mono-fonts dejavu-serif-fonts dejavu-fonts-common libjpeg-devel zlib-devel openssl-devel
RUN yum install -y libyaml-devel glibc-headers autoconf gcc gcc-c++ glibc-devel readline-devel libffi-devel automake libtool bison sqlite-devel cmake

## Update all packages
RUN yum update -y

## Set up upstream Ruby
RUN curl -O https://cache.ruby-lang.org/pub/ruby/2.5/ruby-2.5.6.tar.gz
RUN tar -xzpvf ruby-2.5.6.tar.gz
RUN cd ruby-2.5.6; ./configure; make; make install

## Check out a copy of the puppet components for building
RUN git clone https://github.com/puppetlabs/pl-build-tools-vanagon.git
RUN git clone https://github.com/puppetlabs/puppet-agent.git
RUN git clone https://github.com/puppetlabs/puppet-runtime.git

## Checkout latest tags
# pl-build-tools-vanagon doesn't tag :-|
RUN cd pl-build-tools-vanagon
RUN cd puppet-agent && git describe --tags | xargs git checkout
RUN cd puppet-runtime && git describe --tags | xargs git checkout

## Keep some cruft off of the system
RUN /bin/bash -l -c 'echo "gem: --no-document" | tee -a $HOME/.gemrc'

## Install the gems
RUN /bin/bash -l -c 'gem install bundler'
RUN /bin/bash -l -c 'cd pl-build-tools-vanagon && bundle install'
RUN /bin/bash -l -c 'cd puppet-agent && bundle install'
RUN /bin/bash -l -c 'cd puppet-runtime && bundle install'

## Build vanagon tools
RUN /bin/bash -l -c 'cd pl-build-tools-vanagon && VANAGON_USE_MIRRORS=n build -e local pl-gcc el-7-x86_64'
RUN /bin/bash -l -c 'cd pl-build-tools-vanagon && VANAGON_USE_MIRRORS=n build -e local pl-cmake el-7-x86_64'
RUN /bin/bash -l -c 'cd pl-build-tools-vanagon && VANAGON_USE_MIRRORS=n build -e local pl-gettext el-7-x86_64'
RUN /bin/bash -l -c 'cd pl-build-tools-vanagon && VANAGON_USE_MIRRORS=n build -e local pl-ruby el-7-x86_64'
RUN cd pl-build-tools-vanagon && find output -name *.rpm | xargs yum -y install

## Build runtime
## Set to system openssl due to build issues
RUN for x in puppet-runtime/configs/projects/_shared-*; do echo 'proj.setting(:system_openssl, true)' >> $x; done

RUN /bin/bash -l -c 'cd puppet-runtime && bundle install'
RUN /bin/bash -l -c 'cd puppet-runtime && VANAGON_USE_MIRRORS=n build -e local agent-runtime-master el-7-x86_64'

## Build agent

# Things only needed by the agent build that break the runtime builds
RUN /bin/bash -l -c 'cd pl-build-tools-vanagon && VANAGON_USE_MIRRORS=n build -e local pl-openssl el-7-x86_64'
RUN /bin/bash -l -c 'cd pl-build-tools-vanagon && VANAGON_USE_MIRRORS=n build -e local pl-boost el-7-x86_64'
RUN /bin/bash -l -c 'cd pl-build-tools-vanagon && VANAGON_USE_MIRRORS=n build -e local pl-yaml-cpp el-7-x86_64'
RUN cd pl-build-tools-vanagon && find output -name *.rpm | xargs yum -y install
RUN /bin/bash -l -c 'cd pl-build-tools-vanagon && VANAGON_USE_MIRRORS=n build -e local pl-curl el-7-x86_64'

# It turns out that vanagon diffs the filesystem to figure out what to include in the packages :-|
RUN yum remove -y 'pl-*'
RUN rm -rf /opt/pl-* /opt/puppet*

# Set up a local YUM repo for puppet-agent to build from
RUN mkdir /tmp/repo
RUN find /pl-build-tools-vanagon/output -name "*.rpm" -exec cp {} /tmp/repo \;
RUN /bin/bash -l -c 'cd /tmp/repo && createrepo .'
RUN echo -e "[pl-local]\nbaseurl=file:///tmp/repo\ngpgcheck=0" > /etc/yum.repos.d/pl-local.repo

# The facter tests break due to something wrong with the gem path
RUN sed -i 's/^[[:space:]]*tests[[:space:]]*$/[]/' puppet-agent/configs/components/facter.rb

# Point to the local runtime build
RUN echo "{\"location\":\"file:///puppet-runtime/output\",\"version\":\"`ls puppet-runtime/output/agent-runtime-*master*.json | head -1 | sed -e 's/.*master-\(.*\)\.el-7.*/\1/'`\"}" > puppet-agent/configs/components/puppet-runtime.json

# Install required packages
RUN yum -y install pl-curl pl-cmake pl-gcc pl-gettext pl-boost

RUN rm -rf /opt/puppetlabs

# Actually try to build the agent!
RUN /bin/bash -l -c 'cd puppet-agent && VANAGON_USE_MIRRORS=n build -e local puppet-agent el-7-x86_64'

# Drop into a shell for building
CMD /bin/bash
