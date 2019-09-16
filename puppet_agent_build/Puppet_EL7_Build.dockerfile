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

RUN yum install -y sudo selinux-policy-targeted selinux-policy-devel policycoreutils policycoreutils-python

## Ensure that the 'puppet_build' can sudo to root for RVM
RUN echo 'Defaults:puppet_build !requiretty' >> /etc/sudoers
RUN echo 'puppet_build ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers
RUN useradd -b /home -G wheel -m -c "Build User" -s /bin/bash -U puppet_build
RUN rm -rf /etc/security/limits.d/*.conf

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

## Set up RVM
RUN runuser puppet_build -l -c "echo 'gem: --no-document' > .gemrc"
RUN runuser puppet_build -l -c "for i in {1..5}; do { gpg2 --keyserver  hkp://pool.sks-keyservers.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 || gpg2 --keyserver hkp://pgp.mit.edu --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 || gpg2 --keyserver hkp://keys.gnupg.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3; } && break || sleep 1; done"
RUN runuser puppet_build -l -c "for i in {1..5}; do { gpg2 --keyserver  hkp://pool.sks-keyservers.net --recv-keys 7D2BAF1CF37B13E2069D6956105BD0E739499BDB || gpg2 --keyserver hkp://pgp.mit.edu --recv-keys 7D2BAF1CF37B13E2069D6956105BD0E739499BDB || gpg2 --keyserver hkp://keys.gnupg.net --recv-keys 7D2BAF1CF37B13E2069D6956105BD0E739499BDB; } && break || sleep 1; done"
RUN runuser puppet_build -l -c "curl -sSL https://raw.githubusercontent.com/rvm/rvm/stable/binscripts/rvm-installer -o rvm-installer && curl -sSL https://raw.githubusercontent.com/rvm/rvm/stable/binscripts/rvm-installer.asc -o rvm-installer.asc && gpg2 --verify rvm-installer.asc rvm-installer && bash rvm-installer"
RUN runuser puppet_build -l -c "rvm install 2.5 --disable-binary"
RUN runuser puppet_build -l -c "rvm use --default 2.5"

## Check out a copy of the puppet components for building
RUN runuser puppet_build -l -c "git clone https://github.com/puppetlabs/pl-build-tools-vanagon.git"
RUN runuser puppet_build -l -c "git clone https://github.com/puppetlabs/puppet-agent.git"
RUN runuser puppet_build -l -c "git clone https://github.com/puppetlabs/puppet-runtime.git"

## Checkout latest tags
RUN runuser puppet_build -l -c "cd pl-build-tools-vanagon && git checkout $(git describe --tags)"
RUN runuser puppet_build -l -c "cd puppet-agent && git checkout $(git describe --tags)"
RUN runuser puppet_build -l -c "cd puppet-runtime && git checkout $(git describe --tags)"

## Install the gems
RUN runuser puppet_build -l -c "cd pl-build-tools-vanagon && bundle install"
RUN runuser puppet_build -l -c "cd puppet-agent && bundle install"
RUN runuser puppet_build -l -c "cd puppet-runtime && bundle install"

## Build vanagon tools
RUN runuser puppet_build -l -c "cd pl-build-tools-vanagon && rvmsudo VANAGON_USE_MIRRORS=n bundle exec build -e local pl-gcc el-7-x86_64"
RUN runuser puppet_build -l -c "cd pl-build-tools-vanagon && rvmsudo VANAGON_USE_MIRRORS=n bundle exec build -e local pl-cmake el-7-x86_64"
RUN runuser puppet_build -l -c "cd pl-build-tools-vanagon && rvmsudo VANAGON_USE_MIRRORS=n bundle exec build -e local pl-ruby el-7-x86_64"
RUN runuser puppet_build -l -c "cd pl-build-tools-vanagon && find output -name *.rpm | xargs sudo yum -y install"

## Build runtime
RUN runuser puppet_build -l -c "cd puppet-runtime && bundle install"
RUN runuser puppet_build -l -c "cd puppet-runtime && rvmsudo VANAGON_USE_MIRRORS=n bundle exec build -e local agent-runtime-6.4.x el-7-x86_64"
RUN runuser puppet_build -l -c "cd puppet-runtime && rvmsudo VANAGON_USE_MIRRORS=n bundle exec build -e local agent-runtime-master el-7-x86_64"
RUN runuser puppet_build -l -c "sudo tar -czpvf /root/opt_puppetlabs_backup.tgz /opt/puppetlabs"
RUN runuser puppet_build -l -c "sudo rm -rf /opt/puppetlabs"

## Build agent
# Point to the local runtime build
RUN runuser puppet_build -l -c "cd puppet-agent && sed -i 's|http://.*/artifacts/|file:///home/puppet_build/puppet-runtime/output|' configs/components/puppet-runtime.json"

# Things only needed by the agent build that break the runtime builds
RUN runuser puppet_build -l -c "cd pl-build-tools-vanagon && rvmsudo VANAGON_USE_MIRRORS=n bundle exec build -e local pl-openssl el-7-x86_64"
RUN runuser puppet_build -l -c "cd pl-build-tools-vanagon && rvmsudo VANAGON_USE_MIRRORS=n bundle exec build -e local pl-boost el-7-x86_64"
RUN runuser puppet_build -l -c "cd pl-build-tools-vanagon && find output -name *.rpm | xargs sudo yum -y install"
RUN runuser puppet_build -l -c "cd pl-build-tools-vanagon && rvmsudo VANAGON_USE_MIRRORS=n bundle exec build -e local pl-curl el-7-x86_64"
RUN runuser puppet_build -l -c "cd pl-build-tools-vanagon && rvmsudo VANAGON_USE_MIRRORS=n bundle exec build -e local pl-yaml-cpp el-7-x86_64"
RUN runuser puppet_build -l -c "cd pl-build-tools-vanagon && find output -name *.rpm | xargs sudo yum -y install"

# Work around leatherman insanity
RUN runuser puppet_build -l -c "echo /opt/pl-build-tools/lib | sudo tee -a /etc/ld.so.conf && echo /opt/pl-build-tools/lib64 | sudo tee -a /etc/ld.so.conf && sudo ldconfig"

#### TODO: The facter build segfaults in the tests
RUN runuser puppet_build -l -c "cd puppet-agent && rvmsudo VANAGON_USE_MIRRORS=n bundle exec build -e local puppet-agent el-7-x86_64"

# Drop into a shell for building
CMD /bin/bash -c "su -l puppet_build"
