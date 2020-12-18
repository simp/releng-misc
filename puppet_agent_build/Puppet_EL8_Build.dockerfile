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
FROM centos:8 AS ruby
ENV container docker

RUN yum -y groupinstall "Development Tools"
RUN yum -y install wget openssl-devel

RUN curl -O https://cache.ruby-lang.org/pub/ruby/2.5/ruby-2.5.8.tar.gz
RUN tar -xzpvf ruby-2.5.8.tar.gz

WORKDIR /ruby-2.5.8
RUN ./configure && make && make install
RUN /bin/bash -l -c 'gem install bundler'

FROM centos:8 AS puppet-runtime
ENV container docker

COPY --from=ruby /usr/local/bin /usr/local/bin
COPY --from=ruby /usr/local/include /usr/local/include
COPY --from=ruby /usr/local/lib /usr/local/lib
COPY --from=ruby /usr/local/share /usr/local/share

RUN yum -y groupinstall "Development Tools"
RUN yum -y install wget openssl-devel which
RUN yum -y install cmake gcc gettext

RUN /bin/bash -l -c 'echo "gem: --no-document" | tee -a $HOME/.gemrc'

RUN mkdir /tmp/repo

RUN git clone https://github.com/puppetlabs/puppet-runtime.git

WORKDIR /puppet-runtime
RUN git describe --tags | xargs git checkout
RUN /bin/bash -l -c 'bundle install'
RUN for x in configs/projects/_shared-*; do echo 'proj.setting(:system_openssl, true)' >> $x; done
RUN sed -i '/plat\.add_build_repository/d' configs/platforms/*.rb
RUN /bin/bash -l -c 'VANAGON_USE_MIRRORS=n build -e local agent-runtime-main el-8-x86_64'

FROM centos:8 as pxp-agent
ARG PXP_AGENT_VERSION=latest
ENV pxp_agent_version $PXP_AGENT_VERSION

ENV container docker

COPY --from=ruby /usr/local/bin /usr/local/bin
COPY --from=ruby /usr/local/include /usr/local/include
COPY --from=ruby /usr/local/lib /usr/local/lib
COPY --from=ruby /usr/local/share /usr/local/share

RUN yum -y groupinstall "Development Tools"
RUN yum -y install wget openssl openssl-devel which
RUN yum -y install cmake gcc gettext

RUN /bin/bash -l -c 'echo "gem: --no-document" | tee -a $HOME/.gemrc'

COPY --from=puppet-runtime /puppet-runtime/output /tmp/puppet-runtime

RUN git clone https://github.com/puppetlabs/pxp-agent-vanagon.git

WORKDIR /pxp-agent-vanagon
RUN echo "One: $pxp_agent_version"
RUN echo "Two: $PXP_AGENT_VERSION"
RUN if [ "$pxp_agent_version" == 'latest' ]; then git checkout $(git describe --tags $(git rev-list --tags --max-count=1)); else git checkout "$pxp_agent_version"; fi
RUN git describe --tags | xargs git checkout
RUN /bin/bash -l -c 'bundle install'
#RUN sed -i 's/^[[:space:]]*tests[[:space:]]*$/[]/' configs/components/facter.rb

RUN echo "{\"location\":\"file:///tmp/puppet-runtime\",\"version\":\"`ls /tmp/puppet-runtime/agent-runtime-*main*.json | head -1 | sed -e 's/.*main-\(.*\)\.el-8.*/\1/'`\"}" > configs/components/puppet-runtime.json

RUN sed -i '/plat\.add_build_repository/d' configs/platforms/*.rb

RUN /bin/bash -l -c 'gem install rspec mocha'

RUN /bin/bash -l -c 'VANAGON_USE_MIRRORS=n build -e local pxp-agent el-8-x86_64'

CMD /bin/bash

FROM centos:8 as puppet-agent
ARG PUPPET_VERSION=latest
ENV puppet_version $PUPPET_VERSION

ENV container docker

COPY --from=ruby /usr/local/bin /usr/local/bin
COPY --from=ruby /usr/local/include /usr/local/include
COPY --from=ruby /usr/local/lib /usr/local/lib
COPY --from=ruby /usr/local/share /usr/local/share

RUN yum -y groupinstall "Development Tools"
RUN yum -y install wget openssl openssl-devel which
RUN yum -y install cmake gcc gettext

RUN /bin/bash -l -c 'echo "gem: --no-document" | tee -a $HOME/.gemrc'

COPY --from=pxp-agent /pxp-agent-vanagon/output /tmp/pxp-agent
COPY --from=puppet-runtime /puppet-runtime/output /tmp/puppet-runtime

RUN git clone https://github.com/puppetlabs/puppet-agent.git

WORKDIR /puppet-agent
RUN if [ "$puppet_version" == 'latest' ]; then git checkout $(git describe --tags $(git rev-list --tags --max-count=1)); else git checkout "$puppet_version"; fi
RUN git describe --tags | xargs git checkout
RUN /bin/bash -l -c 'bundle install'
#RUN sed -i 's/^[[:space:]]*tests[[:space:]]*$/[]/' configs/components/facter.rb

RUN echo "{\"location\":\"file:///tmp/puppet-runtime\",\"version\":\"`ls /tmp/puppet-runtime/agent-runtime-*main*.json | head -1 | sed -e 's/.*main-\(.*\)\.el-8.*/\1/'`\"}" > configs/components/puppet-runtime.json
RUN echo "{\"location\":\"file:///tmp/pxp-agent\",\"version\":\"`ls /tmp/pxp-agent/pxp-agent-*.json | head -1 | sed -e 's/.*-\([[:digit:]]\+\)\.el-8.*/\1/'`\"}" > configs/components/pxp-agent.json

RUN sed -i '/plat\.add_build_repository/d' configs/platforms/*.rb

RUN /bin/bash -l -c 'gem install rspec mocha'

RUN /bin/bash -l -c 'VANAGON_USE_MIRRORS=n build -e local puppet-agent el-8-x86_64'

CMD /bin/bash
